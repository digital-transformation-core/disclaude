import { Client, GatewayIntentBits, Partials } from "discord.js";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";

// --- Config ---
const DISCORD_TOKEN = process.env.DISCORD_TOKEN;
const ALLOWED_USER_ID = process.env.DISCORD_ALLOWED_USER;
const CLAUDE_MODEL = process.env.CLAUDE_MODEL || "opus";
const WORKSPACE = process.env.WORKSPACE || join(process.env.HOME, ".claude-discord/workspace");
const DATA_DIR = join(process.env.HOME, ".discord-claude");
const SESSIONS_FILE = join(DATA_DIR, "sessions.json");
const TIMEOUT_MS = 300_000;
const STREAM_EDIT_MS = 900; // Discord edit interval (rate limit: ~5 edits/5s)

if (!DISCORD_TOKEN) {
  console.error("Set DISCORD_TOKEN env var");
  process.exit(1);
}

// --- Session store ---
if (!existsSync(DATA_DIR)) mkdirSync(DATA_DIR, { recursive: true });
let sessionCache = null;

function loadSessions() {
  if (sessionCache) return sessionCache;
  try { sessionCache = JSON.parse(readFileSync(SESSIONS_FILE, "utf8")); }
  catch { sessionCache = {}; }
  return sessionCache;
}
function saveSessions() {
  if (!sessionCache) return;
  const tmp = SESSIONS_FILE + ".tmp";
  writeFileSync(tmp, JSON.stringify(sessionCache, null, 2));
  renameSync(tmp, SESSIONS_FILE);
}
function getSessionId(chId) { return loadSessions()[chId] || null; }
function setSessionId(chId, sid) { loadSessions()[chId] = sid; saveSessions(); }
function clearSession(chId) { delete loadSessions()[chId]; saveSessions(); }

// --- Process cleanup ---
const activeProcs = new Map();
function cleanup() {
  for (const [, proc] of activeProcs) proc.kill("SIGTERM");
  activeProcs.clear();
}
process.on("SIGINT", () => { cleanup(); process.exit(0); });
process.on("SIGTERM", () => { cleanup(); process.exit(0); });

// --- Workspace context ---
let systemPromptCache = null;
function buildSystemPrompt() {
  if (systemPromptCache) return systemPromptCache;
  const files = ["SOUL.md", "MEMORY.md", "IDENTITY.md", "USER.md", "TOOLS.md"];
  const sections = [];
  for (const file of files) {
    try {
      const content = readFileSync(join(WORKSPACE, file), "utf8").trim();
      if (content) {
        const t = content.length > 8000 ? content.slice(0, 8000) + "\n...(truncated)" : content;
        sections.push(`## ${file}\n${t}`);
      }
    } catch {}
  }
  const ws = sections.length > 0 ? "\n\n# Workspace Context\n\n" + sections.join("\n\n---\n\n") : "";
  const name = process.env.SYSTEM_PROMPT_NAME || "Claude";
  systemPromptCache = `You are ${name}, a personal assistant communicating via Discord.
Keep responses concise and conversational — this is chat, not a document.
You have full conversation history in this session. Each Discord channel/thread has its own persistent session.
When the user says /new, start fresh (the session will be reset).${ws}`;
  return systemPromptCache;
}

// --- Run claude with real-time streaming ---
const busy = new Set();

function runClaude(channelId, text, onDelta) {
  return new Promise((resolve) => {
    const existingSession = getSessionId(channelId);
    const isResume = !!existingSession;

    const args = [
      "-p",
      "--output-format", "stream-json",
      "--include-partial-messages",
      "--verbose",
      "--model", CLAUDE_MODEL,
      "--permission-mode", "bypassPermissions",
    ];

    if (isResume) {
      args.push("--resume", existingSession);
    } else {
      args.push("--append-system-prompt", buildSystemPrompt());
    }

    const proc = spawn("claude", args, {
      stdio: ["pipe", "pipe", "pipe"],
      env: process.env,
      cwd: WORKSPACE,
    });

    activeProcs.set(channelId, proc);

    let sessionId = existingSession;
    let fullText = "";
    let resultText = "";
    let isError = false;

    const rl = createInterface({ input: proc.stdout });

    rl.on("line", (line) => {
      try {
        const d = JSON.parse(line);
        if (d.session_id) sessionId = d.session_id;

        // Stream deltas — the real-time text chunks
        if (d.type === "stream_event") {
          const evt = d.event;
          if (evt?.type === "content_block_delta" && evt.delta?.type === "text_delta") {
            fullText += evt.delta.text;
            onDelta?.(fullText);
          }
        }

        if (d.type === "result") {
          if (d.is_error) isError = true;
          if (d.result) resultText = d.result;
          if (d.session_id) sessionId = d.session_id;
        }
      } catch {}
    });

    proc.stderr.on("data", () => {});

    const timeout = setTimeout(() => {
      proc.kill("SIGTERM");
      setTimeout(() => { try { proc.kill("SIGKILL"); } catch {} }, 5000);
    }, TIMEOUT_MS);

    proc.on("close", (code, signal) => {
      clearTimeout(timeout);
      activeProcs.delete(channelId);
      rl.close();

      if (signal === "SIGTERM" || signal === "SIGKILL") {
        resolve({ text: fullText || "(timed out)", sessionId, error: true });
        return;
      }
      resolve({
        text: resultText || fullText || "(no response)",
        sessionId,
        error: isError || (code !== 0 && code !== null),
      });
    });

    proc.on("error", (err) => {
      clearTimeout(timeout);
      activeProcs.delete(channelId);
      resolve({ text: `Failed to start: ${err.message}`, sessionId: null, error: true });
    });

    proc.stdin.write(text);
    proc.stdin.end();
  });
}

// --- Discord helpers ---
async function sendFinalLong(channel, text, existingMsg) {
  const maxLen = 1900;
  if (text.length <= maxLen) {
    await existingMsg.edit(text).catch(() => {});
    return;
  }
  // Edit first chunk into existing message, send rest as new messages
  let remaining = text;
  const first = remaining.slice(0, maxLen);
  remaining = remaining.slice(maxLen);
  await existingMsg.edit(first).catch(() => {});
  while (remaining.length > 0) {
    let end = maxLen;
    if (remaining.length > maxLen) {
      const nl = remaining.lastIndexOf("\n", maxLen);
      if (nl > maxLen * 0.5) end = nl;
    }
    await channel.send(remaining.slice(0, end));
    remaining = remaining.slice(end);
  }
}

// --- Discord bot ---
const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.DirectMessages,
    GatewayIntentBits.MessageContent,
  ],
  partials: [Partials.Channel],
});

client.on("ready", () => {
  console.log(`Bot online as ${client.user.tag}`);
  console.log(`Workspace: ${WORKSPACE} | Model: ${CLAUDE_MODEL}`);
  console.log(`Sessions: ${Object.keys(loadSessions()).length} persisted`);
});

client.on("messageCreate", async (message) => {
  if (message.author.bot) return;
  if (ALLOWED_USER_ID && message.author.id !== ALLOWED_USER_ID) return;

  const isDM = !message.guild;
  const isThread = message.channel.isThread?.();
  const isMentioned = message.mentions.has(client.user);
  if (!isDM && !isThread && !isMentioned) return;

  let text = message.content
    .replace(new RegExp(`<@!?${client.user.id}>`, "g"), "")
    .trim();
  if (!text) return;

  const channelId = message.channel.id;

  if (text.toLowerCase() === "/new" || text.toLowerCase() === "new session") {
    clearSession(channelId);
    await message.reply("Session cleared.");
    return;
  }

  if (busy.has(channelId)) {
    await message.reply("Still working on the previous message...");
    return;
  }

  const hasSession = !!getSessionId(channelId);
  console.log(`[${channelId}] ${message.author.username}: ${text.slice(0, 80)}${hasSession ? " (resume)" : " (new)"}`);
  busy.add(channelId);

  // Determine reply channel (create thread for channel mentions)
  let replyChannel = message.channel;
  let createdThread = false;
  if (!isDM && !isThread && isMentioned) {
    try {
      replyChannel = await message.startThread({
        name: text.slice(0, 90) || "Jarvis",
        autoArchiveDuration: 60,
      });
      createdThread = true;
    } catch {}
  }

  try {
    // Send initial placeholder
    let replyMsg;
    if (createdThread) {
      replyMsg = await replyChannel.send("⌛ Thinking...");
    } else {
      replyMsg = await message.reply("⌛ Thinking...");
    }

    // Simple streaming: edit message with current text every 900ms
    let currentText = "";
    let lastShown = "";
    let editTimer = null;

    const doEdit = () => {
      if (currentText === lastShown) return;
      lastShown = currentText;
      const display = currentText.length > 1900 ? currentText.slice(0, 1900) : currentText;
      replyMsg.edit(display).catch(() => {});
    };

    // Tick loop: fire edit at fixed interval while streaming
    editTimer = setInterval(doEdit, STREAM_EDIT_MS);

    let result = await runClaude(channelId, text, (text) => {
      currentText = text;
    });

    clearInterval(editTimer);
    editTimer = null;

    // Save session
    if (result.sessionId && !result.error) {
      setSessionId(channelId, result.sessionId);
      if (createdThread) setSessionId(replyChannel.id, result.sessionId);
    }

    // Auto-retry on resume failure
    if (result.error && hasSession) {
      console.log(`[${channelId}] Resume failed, retrying fresh`);
      clearSession(channelId);
      currentText = "";
      lastShown = "";
      await replyMsg.edit("🔄 Retrying...").catch(() => {});
      editTimer = setInterval(doEdit, STREAM_EDIT_MS);
      result = await runClaude(channelId, text, (t) => { currentText = t; });
      clearInterval(editTimer);
      if (result.sessionId && !result.error) {
        setSessionId(channelId, result.sessionId);
        if (createdThread) setSessionId(replyChannel.id, result.sessionId);
      }
    }

    // Final edit — only if content differs from last streamed edit
    if (result.text !== lastShown) {
      await sendFinalLong(replyChannel, result.text, replyMsg);
    }

    console.log(`[${channelId}] OK (${result.text.length}c, session=${result.sessionId?.slice(0, 8) || "?"})`);
  } catch (err) {
    console.error(`Error:`, err.message);
    await message.reply("Something went wrong.").catch(() => {});
  } finally {
    busy.delete(channelId);
  }
});

client.login(DISCORD_TOKEN);
