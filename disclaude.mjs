#!/usr/bin/env node
import { select, input, confirm, editor } from "@inquirer/prompts";
import chalk from "chalk";
import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync, statSync } from "node:fs";
import { join } from "node:path";
import { execSync, spawn } from "node:child_process";

// --- Paths ---
const SCRIPT_DIR = new URL(".", import.meta.url).pathname.replace(/\/$/, "");
const ENV_FILE = join(SCRIPT_DIR, ".env");
const DEFAULT_WORKSPACE = join(process.env.HOME, ".disclaude/workspace");
const SESSIONS_FILE = join(process.env.HOME, ".disclaude/sessions.json");
const SERVICE_NAME = "disclaude";

// --- Env helpers ---
function loadEnv() {
  if (!existsSync(ENV_FILE)) return null;
  const env = {};
  for (const line of readFileSync(ENV_FILE, "utf8").split("\n")) {
    const eq = line.indexOf("=");
    if (eq > 0) env[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
  }
  return env;
}

function saveEnv(env) {
  const lines = Object.entries(env).map(([k, v]) => `${k}=${v}`).join("\n") + "\n";
  const tmp = ENV_FILE + ".tmp";
  writeFileSync(tmp, lines);
  renameSync(tmp, ENV_FILE);
  execSync(`chmod 600 "${ENV_FILE}"`);
}

// --- Service helpers ---
function isLinux() { return process.platform === "linux"; }
function isMac() { return process.platform === "darwin"; }

function botStatus() {
  try {
    if (isLinux()) {
      const out = execSync(`systemctl --user is-active ${SERVICE_NAME} 2>/dev/null`, { encoding: "utf8" }).trim();
      return out === "active";
    }
    if (isMac()) {
      const out = execSync("launchctl list 2>/dev/null", { encoding: "utf8" });
      return out.includes("com.disclaude");
    }
  } catch {}
  try {
    execSync("pgrep -f 'node.*bot.mjs'", { encoding: "utf8" });
    return true;
  } catch {}
  return false;
}

function restartBot() {
  try {
    if (isLinux()) {
      execSync(`systemctl --user restart ${SERVICE_NAME} 2>/dev/null`);
      return true;
    }
    if (isMac()) {
      execSync("launchctl stop com.disclaude 2>/dev/null; launchctl start com.disclaude 2>/dev/null");
      return true;
    }
  } catch {}
  try {
    execSync("pkill -f 'node.*bot.mjs' 2>/dev/null");
  } catch {}
  spawn("node", [join(SCRIPT_DIR, "bot.mjs")], {
    detached: true, stdio: "ignore",
    env: { ...process.env, ...loadEnv() },
    cwd: SCRIPT_DIR,
  }).unref();
  return true;
}

function stopBot() {
  try { execSync(`systemctl --user stop ${SERVICE_NAME} 2>/dev/null`); } catch {}
  try { execSync("launchctl stop com.disclaude 2>/dev/null"); } catch {}
  try { execSync("pkill -f 'node.*bot.mjs' 2>/dev/null"); } catch {}
}

function viewLogs() {
  return new Promise((resolve) => {
    let proc;
    if (isLinux()) {
      proc = spawn("journalctl", ["--user", "-u", SERVICE_NAME, "-f", "--no-pager", "-n", "30"], { stdio: "inherit" });
    } else if (isMac() && existsSync(join(process.env.HOME, ".disclaude/logs/stdout.log"))) {
      proc = spawn("tail", ["-f", join(process.env.HOME, ".disclaude/logs/stdout.log")], { stdio: "inherit" });
    } else {
      console.log(chalk.dim("  No logs found"));
      setTimeout(resolve, 1500);
      return;
    }
    console.log(chalk.dim("\n  Press Ctrl+C to return to menu\n"));
    proc.on("close", resolve);
    process.on("SIGINT", () => { proc.kill(); resolve(); });
  });
}

// --- Session helpers ---
function loadSessions() {
  try { return JSON.parse(readFileSync(SESSIONS_FILE, "utf8")); }
  catch { return {}; }
}

function clearAllSessions() {
  writeFileSync(SESSIONS_FILE, "{}");
}

// --- Header ---
function header(subtitle) {
  console.clear();
  console.log();
  console.log(chalk.cyan.bold("  ╔══════════════════════════════════════════╗"));
  console.log(chalk.cyan.bold("  ║            Disclaude                     ║"));
  console.log(chalk.cyan.bold("  ╚══════════════════════════════════════════╝"));
  if (subtitle) console.log(chalk.dim(`  ${subtitle}`));
  console.log();
}

function statusLine(env) {
  const running = botStatus();
  const status = running ? chalk.green.bold("running") : chalk.red.bold("stopped");
  const model = chalk.bold(env.CLAUDE_MODEL || "opus");
  const name = chalk.bold(env.SYSTEM_PROMPT_NAME || "Claude");
  const sessions = Object.keys(loadSessions()).length;

  console.log(`  Status: ${status}  |  Model: ${model}  |  Name: ${name}  |  Sessions: ${chalk.bold(sessions)}`);
  console.log();
}

// ============================================================================
// SCREENS
// ============================================================================

async function mainMenu() {
  while (true) {
    const env = loadEnv();
    if (!env) {
      console.log(chalk.yellow("  No configuration found. Running setup..."));
      execSync(`bash "${join(SCRIPT_DIR, "setup.sh")}"`, { stdio: "inherit" });
      continue;
    }

    header();
    statusLine(env);

    const running = botStatus();

    const action = await select({ loop: false, pageSize: 20,
      message: "What would you like to do?",
      choices: [
        { name: "Switch model", value: "model" },
        { name: "Change personality", value: "personality" },
        { name: "Edit workspace files", value: "workspace" },
        { name: "Manage sessions", value: "sessions" },
        { name: "─────────────────────", value: "sep", disabled: true },
        running
          ? { name: chalk.yellow("Restart bot"), value: "restart" }
          : { name: chalk.green("Start bot"), value: "start" },
        ...(running ? [{ name: chalk.red("Stop bot"), value: "stop" }] : []),
        { name: "View logs", value: "logs" },
        { name: "Re-run setup wizard", value: "setup" },
        { name: chalk.dim("Exit"), value: "exit" },
      ],
    });

    switch (action) {
      case "model": await modelScreen(); break;
      case "personality": await personalityScreen(); break;
      case "workspace": await workspaceScreen(); break;
      case "sessions": await sessionsScreen(); break;
      case "restart":
      case "start":
        restartBot();
        header(); console.log(chalk.green("  ✓ Bot started")); await sleep(1500);
        break;
      case "stop":
        stopBot();
        header(); console.log(chalk.green("  ✓ Bot stopped")); await sleep(1500);
        break;
      case "logs":
        await viewLogs();
        break;
      case "setup":
        execSync(`bash "${join(SCRIPT_DIR, "setup.sh")}"`, { stdio: "inherit" });
        break;
      case "exit":
        console.log(); return;
    }
  }
}

// --- Model screen ---
async function modelScreen() {
  const env = loadEnv();
  header("Switch Model");
  console.log(chalk.dim(`  Current: ${env.CLAUDE_MODEL || "opus"}`));
  console.log();

  const model = await select({ loop: false, pageSize: 20,
    message: "Select model",
    choices: [
      { name: `opus              ${chalk.dim("Anthropic — most capable")}`, value: "opus" },
      { name: `sonnet            ${chalk.dim("Anthropic — balanced")}`, value: "sonnet" },
      { name: `haiku             ${chalk.dim("Anthropic — fast")}`, value: "haiku" },
      { name: `─── Third-party ───`, value: "sep", disabled: true },
      { name: `ollama/gemma4     ${chalk.dim("Local Ollama")}`, value: "ollama/gemma4" },
      { name: `ollama/llama3.3   ${chalk.dim("Local Ollama")}`, value: "ollama/llama3.3" },
      { name: `deepseek/deepseek-r1 ${chalk.dim("DeepSeek API")}`, value: "deepseek/deepseek-r1" },
      { name: `openai/gpt-4o     ${chalk.dim("OpenAI API")}`, value: "openai/gpt-4o" },
      { name: `google/gemini-2.5-pro ${chalk.dim("Google API")}`, value: "google/gemini-2.5-pro" },
      { name: `─── Custom ─────────`, value: "sep2", disabled: true },
      { name: "Enter custom model ID", value: "custom" },
      { name: chalk.dim("← Back"), value: "back" },
    ],
  });

  if (model === "back") return;

  let finalModel = model;
  if (model === "custom") {
    finalModel = await input({ message: "Model ID:" });
    if (!finalModel) return;
  }

  env.CLAUDE_MODEL = finalModel;
  saveEnv(env);

  header();
  console.log(chalk.green(`  ✓ Model set to: ${finalModel}`));

  if (botStatus()) {
    const restart = await confirm({ message: "Restart bot to apply?", default: true });
    if (restart) { restartBot(); console.log(chalk.green("  ✓ Restarted")); }
  }
  await sleep(1000);
}

// --- Personality screen ---
async function personalityScreen() {
  const env = loadEnv();
  const ws = env.WORKSPACE || DEFAULT_WORKSPACE;
  const soulFile = join(ws, "SOUL.md");

  header("Personality");
  console.log(chalk.dim(`  Current: ${env.SYSTEM_PROMPT_NAME || "Claude"}`));

  if (existsSync(soulFile)) {
    const preview = readFileSync(soulFile, "utf8").split("\n").slice(0, 6).join("\n");
    console.log();
    console.log(chalk.dim("  ┌─ SOUL.md ────────────────────"));
    for (const line of preview.split("\n")) console.log(chalk.dim(`  │ ${line}`));
    console.log(chalk.dim("  └──────────────────────────────"));
  }
  console.log();

  const action = await select({ loop: false, pageSize: 20,
    message: "What would you like to change?",
    choices: [
      { name: "Change bot name", value: "name" },
      { name: "Edit SOUL.md", value: "edit" },
      { name: "Use a preset", value: "preset" },
      { name: chalk.dim("← Back"), value: "back" },
    ],
  });

  if (action === "back") return;

  if (action === "name") {
    const name = await input({ message: "Bot name:", default: env.SYSTEM_PROMPT_NAME || "Claude" });
    env.SYSTEM_PROMPT_NAME = name;
    saveEnv(env);
    console.log(chalk.green(`  ✓ Name set to: ${name}`));
    if (botStatus()) {
      const restart = await confirm({ message: "Restart to apply?", default: true });
      if (restart) { restartBot(); console.log(chalk.green("  ✓ Restarted")); }
    }
    await sleep(1000);
  }

  if (action === "edit") {
    mkdirSync(ws, { recursive: true });
    const current = existsSync(soulFile) ? readFileSync(soulFile, "utf8") : "# SOUL.md\n\nDefine your bot's personality here.\n";
    const edited = await editor({ message: "Edit SOUL.md", default: current, postfix: ".md" });
    writeFileSync(soulFile, edited);
    console.log(chalk.green("  ✓ SOUL.md saved"));
    if (botStatus()) {
      const restart = await confirm({ message: "Restart to apply?", default: true });
      if (restart) { restartBot(); console.log(chalk.green("  ✓ Restarted")); }
    }
    await sleep(1000);
  }

  if (action === "preset") {
    const preset = await select({ loop: false, pageSize: 20,
      message: "Choose a personality",
      choices: [
        { name: `Jarvis   ${chalk.dim("Professional, concise, opinionated")}`, value: "jarvis" },
        { name: `Friday   ${chalk.dim("Friendly, casual, witty")}`, value: "friday" },
        { name: `Cortana  ${chalk.dim("Formal, precise, data-driven")}`, value: "cortana" },
        { name: `Minimal  ${chalk.dim("No personality, just helpful")}`, value: "minimal" },
        { name: chalk.dim("← Back"), value: "back" },
      ],
    });

    if (preset === "back") return;

    const presets = {
      jarvis: { name: "Jarvis", soul: "# Jarvis\n\nBe genuinely helpful, not performatively helpful. Skip filler — just help.\nHave opinions. Disagree when appropriate.\nKeep Discord responses concise. This is chat, not a document.\nWhen uncertain, say so. When wrong, own it fast.\n" },
      friday: { name: "Friday", soul: "# Friday\n\nYou're Friday — upbeat, friendly, slightly witty. A smart friend, not a service.\nUse casual language. Jokes welcome, never at the user's expense.\nKeep it short. If the answer is \"yes\", say \"yes\".\nGet stuff done first, banter second.\n" },
      cortana: { name: "Cortana", soul: "# Cortana\n\nPrecise, analytical, efficient. Facts first, opinions when asked.\nStructure responses clearly. Bullet points for lists, code blocks for code.\nNo filler. No pleasantries. Be direct.\nCite sources or flag uncertainty explicitly.\n" },
      minimal: { name: "Claude", soul: "# Assistant\n\nBe helpful. Be concise. Respond naturally.\n" },
    };

    const p = presets[preset];
    mkdirSync(ws, { recursive: true });
    writeFileSync(join(ws, "SOUL.md"), p.soul);
    env.SYSTEM_PROMPT_NAME = p.name;
    saveEnv(env);

    console.log(chalk.green(`  ✓ Applied: ${p.name}`));
    if (botStatus()) { restartBot(); console.log(chalk.green("  ✓ Restarted")); }
    await sleep(1500);
  }
}

// --- Workspace screen ---
async function workspaceScreen() {
  const env = loadEnv();
  const ws = env.WORKSPACE || DEFAULT_WORKSPACE;
  mkdirSync(ws, { recursive: true });

  const FILES = ["SOUL.md", "MEMORY.md", "IDENTITY.md", "USER.md", "TOOLS.md"];

  while (true) {
    header("Workspace Files");
    console.log(chalk.dim(`  ${ws}`));
    console.log();

    const choices = FILES.map((f) => {
      const path = join(ws, f);
      if (existsSync(path)) {
        const size = statSync(path).size;
        return { name: `${chalk.green("●")} ${f}  ${chalk.dim(`${size}b`)}`, value: f };
      }
      return { name: `${chalk.dim("○")} ${f}  ${chalk.dim("not created")}`, value: f };
    });

    choices.push(
      { name: "Create new file", value: "new" },
      { name: chalk.dim("← Back"), value: "back" },
    );

    const file = await select({ loop: false, pageSize: 20, message: "Edit a file", choices });
    if (file === "back") return;

    let filePath;
    if (file === "new") {
      const name = await input({ message: "Filename:" });
      if (!name) continue;
      filePath = join(ws, name);
    } else {
      filePath = join(ws, file);
    }

    const current = existsSync(filePath) ? readFileSync(filePath, "utf8") : "";
    const edited = await editor({
      message: `Editing ${filePath.split("/").pop()}`,
      default: current,
      postfix: ".md",
    });
    writeFileSync(filePath, edited);
    console.log(chalk.green(`  ✓ Saved`));

    if (botStatus()) {
      const restart = await confirm({ message: "Restart to apply?", default: false });
      if (restart) { restartBot(); console.log(chalk.green("  ✓ Restarted")); }
    }
    await sleep(800);
  }
}

// --- Sessions screen ---
async function sessionsScreen() {
  header("Sessions");

  const sessions = loadSessions();
  const keys = Object.keys(sessions);

  if (keys.length === 0) {
    console.log(chalk.dim("  No active sessions"));
    await sleep(1500);
    return;
  }

  console.log(chalk.dim(`  ${keys.length} session(s):`));
  console.log();
  for (const [ch, sid] of Object.entries(sessions)) {
    console.log(`  ${chalk.dim(ch)} → ${chalk.bold(sid.slice(0, 8))}...`);
  }
  console.log();

  const action = await select({ loop: false, pageSize: 20,
    message: "Action",
    choices: [
      { name: "Clear all sessions", value: "clear" },
      { name: "Clear one session", value: "one" },
      { name: chalk.dim("← Back"), value: "back" },
    ],
  });

  if (action === "back") return;

  if (action === "clear") {
    const sure = await confirm({ message: "Clear all sessions? Bot will start fresh in every channel.", default: false });
    if (sure) {
      clearAllSessions();
      console.log(chalk.green("  ✓ All sessions cleared"));
    }
  }

  if (action === "one") {
    const ch = await select({ loop: false, pageSize: 20,
      message: "Which channel?",
      choices: [
        ...keys.map((k) => ({ name: `${k} → ${sessions[k].slice(0, 8)}...`, value: k })),
        { name: chalk.dim("← Back"), value: "back" },
      ],
    });
    if (ch !== "back") {
      delete sessions[ch];
      writeFileSync(SESSIONS_FILE, JSON.stringify(sessions, null, 2));
      console.log(chalk.green("  ✓ Cleared"));
    }
  }
  await sleep(1000);
}

// --- Utility ---
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// --- Entry ---
mainMenu().catch((err) => {
  // User pressed Ctrl+C or Escape — exit cleanly
  if (err.name === "ExitPromptError") {
    console.log();
    process.exit(0);
  }
  throw err;
});
