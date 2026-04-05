# Disclaude

**Talk to Claude Code from Discord.** One file. Real-time streaming. Persistent sessions. Full tool access.

<img src="https://img.shields.io/badge/Claude_Code-CLI-blue?style=flat-square" /> <img src="https://img.shields.io/badge/Discord.js-v14-5865F2?style=flat-square" /> <img src="https://img.shields.io/badge/Node.js-18+-339933?style=flat-square" />

---

## The story

You love Claude. You talk to it every day — brainstorming, note-taking, debugging, researching, planning your life. Then you discovered you could run Claude on Discord, so you set up an orchestrator to bridge the two. It worked beautifully — persistent conversations, workspace memory, personality customization, the whole thing.

Then one morning, Claude stopped responding. **"Third-party apps now draw from your extra usage."** Your orchestrator was spawning too many automated sessions overnight — cron jobs, heartbeat checks, watchdog polling — and Anthropic's servers flagged the pattern. Your subscription still works in the terminal. Just not through the bridge.

But here's the thing: **you're not running a third-party app.** You're running the same `claude` CLI binary, with the same auth, the same model. You just want to talk to it from Discord instead of a terminal window. That's it.

**disclaude is that bridge.** No orchestrator, no background automation, no session spam. Each Discord message spawns one native `claude -p` call — identical to typing in your terminal. When you stop talking, nothing runs. Zero footprint between messages.

Your conversations persist. Your workspace context carries forward. Your SOUL.md personality stays. Claude has full tool access — Bash, file editing, web search, subagents, MCP tools, everything. It streams responses in real-time, creates threads, resumes sessions days later.

It's not a platform. It's not a framework. It's a 320-line bridge that lets you keep your daily habit of talking to Claude — just from Discord.

**If you got rate-limited by the orchestrator game, this is your native transition. The fun continues.**

---

## What it does

- **Streams responses in real-time** — watch Claude think, word by word
- **Persistent sessions** — each channel/thread remembers the full conversation, resume days later
- **Full Claude Code power** — Bash, file editing, web search, subagents, MCP tools — all native
- **Thread support** — @mention creates a thread, replies continue the conversation
- **Workspace context** — SOUL.md (personality), MEMORY.md, TOOLS.md loaded on first message
- **Interactive management panel** — switch models, change personality, manage sessions
- **Cross-platform** — Linux (systemd), macOS (launchd), Windows (manual/pm2)
- **Zero background cost** — no process runs between messages, no cron, no heartbeat

## Requirements

- **Node.js 18+** (or Bun)
- **Claude Code CLI** installed and authenticated (`npm i -g @anthropic-ai/claude-code && claude auth login`)
- **A Discord bot token** ([create one here](https://discord.com/developers/applications))
- **An Anthropic subscription** (Pro/Max) — this uses your Claude Code CLI auth, not an API key

## Quick start

```bash
git clone https://github.com/user/disclaude.git
cd disclaude
npm install   # or: bun install
bash setup.sh
```

The setup wizard checks requirements, guides you through Discord bot creation (or migrates from OpenClaw), and starts the bot as a background service.

## Usage

| Action | How |
|--------|-----|
| Talk in a channel | @mention the bot |
| Talk in DM | Just message it |
| Continue in a thread | Reply in the thread (no @mention needed) |
| Reset a conversation | Say `/new` |
| Manage the bot | `node disclaude.mjs` (or `bun disclaude.mjs`) |

## Management panel

```bash
node disclaude.mjs
```

```
╔══════════════════════════════════════════╗
║            disclaude                       ║
╚══════════════════════════════════════════╝

  Status: running  |  Model: opus  |  Name: Jarvis  |  Sessions: 3

? What would you like to do?
❯ Switch model
  Change personality
  Edit workspace files
  Manage sessions
  ─────────────────────
  Restart bot
  View logs
  Exit
```

**Switch model** — Opus, Sonnet, Haiku, or any third-party: Ollama, DeepSeek, OpenAI, Google, custom model IDs.

**Change personality** — Presets (Jarvis, Friday, Cortana, Minimal) or edit SOUL.md directly with your editor.

## How it works

Each Discord message runs `claude -p --model opus` — the exact same binary and auth you use in your terminal.

```
You (Discord) → bot.mjs → claude -p → Anthropic API → streamed response → Discord
```

- First message creates a session with your workspace context (SOUL.md, MEMORY.md, etc.)
- Every subsequent message uses `--resume` to continue with full history
- Claude exits after each response — zero processes between messages
- Sessions persist on disk indefinitely

## Workspace

Customize Claude's behavior with files in `~/.disclaude/workspace/`:

| File | Purpose |
|------|---------|
| `SOUL.md` | Personality, tone, behavior rules |
| `MEMORY.md` | Persistent memory and context |
| `IDENTITY.md` | Role and identity definition |
| `USER.md` | Info about you |
| `TOOLS.md` | Tool usage guidelines |

## Configuration

All config lives in `.env`:

```
DISCORD_TOKEN=your_bot_token
DISCORD_ALLOWED_USER=your_discord_id
CLAUDE_MODEL=opus
WORKSPACE=~/.disclaude/workspace
SYSTEM_PROMPT_NAME=Jarvis
```

## Service management

**Linux:**
```bash
systemctl --user status disclaude
systemctl --user restart disclaude
journalctl --user -u disclaude -f
```

**macOS:**
```bash
launchctl list | grep claude
tail -f ~/.disclaude/logs/stdout.log
```

## Migrating from OpenClaw

Run `bash setup.sh` — it detects your OpenClaw installation and offers to migrate:
- Copies your Discord bot token (reads, never modifies OpenClaw config)
- Copies workspace files (SOUL.md, MEMORY.md, etc.)
- Stops the OpenClaw gateway
- Starts disclaude as a drop-in replacement

Your OpenClaw config is left untouched. You can switch back anytime.

---

## Current limitations

- **One message at a time per channel** — concurrent messages in the same channel are queued (different channels work in parallel)
- **No scheduled tasks / cron** — no automated background polling or heartbeat checks
- **No MCP loopback server** — Claude uses your globally configured MCP tools, not a gateway-managed tool server
- **No multi-user support** — designed for single-user personal use (one `DISCORD_ALLOWED_USER`)
- **No message history import** — existing OpenClaw conversation history doesn't carry over (sessions start fresh)
- **Discord rate limits streaming** — message edits are capped at ~5/5s by Discord's API, so streaming updates every ~900ms

## Roadmap

Features planned or in consideration:

| Feature | Status |
|---------|--------|
| Telegram channel | `soon` |
| Slack channel | `soon` |
| WhatsApp channel | `soon` |
| Signal channel | `soon` |
| iMessage channel | `soon` |
| Matrix channel | `soon` |
| Web UI channel | `soon` |
| Scheduled tasks / cron | `planned` |
| Multi-user with per-user sessions | `planned` |
| Image / file attachment support | `planned` |
| Voice message transcription | `planned` |
| Conversation export / backup | `planned` |
| MCP loopback server | `considering` |
| Plugin system | `considering` |

---

## License

MIT

## Credits

Born from the frustration of getting rate-limited by orchestrator overhead. If you just want to talk to Claude from Discord without the complexity, this is it.
