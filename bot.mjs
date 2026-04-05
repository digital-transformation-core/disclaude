import { Client, GatewayIntentBits, Partials } from "discord.js";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";

// --- Config ---
const DISCORD_TOKEN = process.env.DISCORD_TOKEN;
const ALLOWED_USER_ID = process.env.DISCORD_ALLOWED_USER;
const CLAUDE_MODEL = process.env.CLAUDE_MODEL || "opus";
const WORKSPACE = process.env.WORKSPACE || join(process.env.HOME, ".disclaude/workspace");
const DATA_DIR = join(process.env.HOME, ".disclaude");
const SESSIONS_FILE = join(DATA_DIR, "sessions.json");
const TIMEOUT_MS = 300_000;
const STREAM_EDIT_MS = 900;

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

/** Load a file from workspace, with optional truncation */
function loadWorkspaceFile(filename, maxChars = 8000) {
  try {
    const content = readFileSync(join(WORKSPACE, filename), "utf8").trim();
    if (!content) return null;
    return content.length > maxChars
      ? content.slice(0, maxChars) + "\n...(truncated)"
      : content;
  } catch { return null; }
}

/**
 * Load channel-specific context files.
 * Looks for files in WORKSPACE/channels/<channelName>/ (e.g. channels/financial/CONTEXT.md)
 * Falls back to WORKSPACE/CHANNEL-<channelName>.md (e.g. CHANNEL-financial.md)
 */
function loadChannelContext(channelName) {
  if (!channelName) return null;
  const sanitized = channelName.toLowerCase().replace(/[^a-z0-9_-]/g, "");
  if (!sanitized) return null;

  const sections = [];

  // Check for channel-specific directory
  const channelDir = join(WORKSPACE, "channels", sanitized);
  if (existsSync(channelDir)) {
    try {
      for (const file of readdirSync(channelDir).sort()) {
        if (!file.endsWith(".md")) continue;
        const content = readFileSync(join(channelDir, file), "utf8").trim();
        if (content) {
          const t = content.length > 6000 ? content.slice(0, 6000) + "\n...(truncated)" : content;
          sections.push(`### ${file}\n${t}`);
        }
      }
    } catch {}
  }

  // Check for single channel context file
  const singleFile = join(WORKSPACE, `CHANNEL-${sanitized}.md`);
  if (existsSync(singleFile)) {
    const content = loadWorkspaceFile(`CHANNEL-${sanitized}.md`, 6000);
    if (content) sections.push(content);
  }

  return sections.length > 0 ? sections.join("\n\n") : null;
}

/**
 * Build system prompt with:
 * - Global workspace files (SOUL.md, MEMORY.md, etc.)
 * - Channel-specific context (if channel name provided)
 * - Channel/thread metadata so Claude knows where it is
 */
function buildSystemPrompt(context) {
  const { channelName, channelTopic, threadName, isDM } = context;

  // Global workspace files
  const globalFiles = ["SOUL.md", "MEMORY.md", "IDENTITY.md", "USER.md", "TOOLS.md"];
  const sections = [];
  for (const file of globalFiles) {
    const content = loadWorkspaceFile(file);
    if (content) sections.push(`## ${file}\n${content}`);
  }
  const globalContext = sections.length > 0
    ? "\n\n# Workspace Context\n\n" + sections.join("\n\n---\n\n")
    : "";

  // Channel-specific context
  const channelCtx = loadChannelContext(channelName);
  const channelSection = channelCtx
    ? `\n\n# Channel Context: #${channelName}\n\n${channelCtx}`
    : "";

  // Where are we?
  let locationHint = "";
  if (isDM) {
    locationHint = "\nYou are in a private DM conversation.";
  } else if (threadName) {
    locationHint = `\nYou are in Discord thread "${threadName}" in channel #${channelName || "unknown"}.`;
    if (channelTopic) locationHint += ` Channel topic: ${channelTopic}`;
    locationHint += "\nContinue the thread's conversation naturally. You have the full history from this thread.";
  } else if (channelName) {
    locationHint = `\nYou are in Discord channel #${channelName}.`;
    if (channelTopic) locationHint += ` Topic: ${channelTopic}`;
  }

  const name = process.env.SYSTEM_PROMPT_NAME || "Claude";
  return `You are ${name}, a personal assistant communicating via Discord.
Keep responses concise and conversational — this is chat, not a document.
You have full conversation history in this session. Each Discord channel/thread has its own persistent session.
Always respond in the same language the user writes in. Match their language naturally.
When the user says /new, start fresh (the session will be reset).${locationHint}${globalContext}${channelSection}`;
}

// --- Run claude with real-time streaming ---
const busy = new Set();

function runClaude(channelId, text, systemPrompt, onDelta) {
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
      args.push("--append-system-prompt", systemPrompt);
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

/** Resolve the parent channel name for a thread */
function resolveChannelInfo(message) {
  const channel = message.channel;
  const isDM = !message.guild;

  if (isDM) {
    return { channelName: null, channelTopic: null, threadName: null, isDM: true };
  }

  // Thread — get parent channel info
  if (channel.isThread?.()) {
    const parent = channel.parent;
    return {
      channelName: parent?.name || null,
      channelTopic: parent?.topic || null,
      threadName: channel.name || null,
      isDM: false,
    };
  }

  // Regular channel
  return {
    channelName: channel.name || null,
    channelTopic: channel.topic || null,
    threadName: null,
    isDM: false,
  };
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
  const channelInfo = resolveChannelInfo(message);
  const label = channelInfo.threadName || channelInfo.channelName || "DM";
  console.log(`[${label}] ${message.author.username}: ${text.slice(0, 80)}${hasSession ? " (resume)" : " (new)"}`);
  busy.add(channelId);

  // Build system prompt with channel context (per-channel, not cached globally)
  const systemPrompt = buildSystemPrompt(channelInfo);

  // Determine reply channel (create thread for channel mentions)
  let replyChannel = message.channel;
  let createdThread = false;
  if (!isDM && !isThread && isMentioned) {
    try {
      replyChannel = await message.startThread({
        name: text.slice(0, 90) || "Claude",
        autoArchiveDuration: 60,
      });
      createdThread = true;
    } catch {}
  }

  try {
    let replyMsg;
    if (createdThread) {
      replyMsg = await replyChannel.send("\u231B Thinking...");
    } else {
      replyMsg = await message.reply("\u231B Thinking...");
    }

    // Streaming
    let currentText = "";
    let lastShown = "";
    const doEdit = () => {
      if (currentText === lastShown) return;
      lastShown = currentText;
      const display = currentText.length > 1900 ? currentText.slice(0, 1900) : currentText;
      replyMsg.edit(display).catch(() => {});
    };
    let editTimer = setInterval(doEdit, STREAM_EDIT_MS);

    let result = await runClaude(channelId, text, systemPrompt, (t) => { currentText = t; });

    clearInterval(editTimer);

    // Save session
    if (result.sessionId && !result.error) {
      setSessionId(channelId, result.sessionId);
      if (createdThread) setSessionId(replyChannel.id, result.sessionId);
    }

    // Auto-retry on resume failure
    if (result.error && hasSession) {
      console.log(`[${label}] Resume failed, retrying fresh`);
      clearSession(channelId);
      currentText = "";
      lastShown = "";
      await replyMsg.edit("\uD83D\uDD04 Retrying...").catch(() => {});
      editTimer = setInterval(doEdit, STREAM_EDIT_MS);
      result = await runClaude(channelId, text, systemPrompt, (t) => { currentText = t; });
      clearInterval(editTimer);
      if (result.sessionId && !result.error) {
        setSessionId(channelId, result.sessionId);
        if (createdThread) setSessionId(replyChannel.id, result.sessionId);
      }
    }

    // Final edit
    if (result.text !== lastShown) {
      await sendFinalLong(replyChannel, result.text, replyMsg);
    }

    console.log(`[${label}] OK (${result.text.length}c, session=${result.sessionId?.slice(0, 8) || "?"})`);
  } catch (err) {
    console.error(`Error:`, err.message);
    await message.reply("Something went wrong.").catch(() => {});
  } finally {
    busy.delete(channelId);
  }
});

client.login(DISCORD_TOKEN);
