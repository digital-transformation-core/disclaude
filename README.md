# Disclaude

Use your Anthropic subscription (Pro/Max) via Discord — same Claude Code CLI, same auth, same behavior as your terminal.

<img src="https://img.shields.io/badge/Claude_Code-CLI-blue?style=flat-square" /> <img src="https://img.shields.io/badge/Discord.js-v14-5865F2?style=flat-square" /> <img src="https://img.shields.io/badge/Node.js-18+-339933?style=flat-square" />

> **Purpose:** Every API call is a genuine, human-initiated Claude Code CLI invocation — identical to typing in a terminal. No API key spoofing, no rate limit circumvention, no automated session farming, no background polling. This project does not bypass, exploit, or abuse any Anthropic service.

## Features

- **Near real-time streaming** — responses stream word by word (limited by Discord's ~5 edits/5s rate limit)
- **Persistent sessions** — each channel/thread remembers the full conversation, resume days later
- **Full Claude Code power** — Bash, file editing, web search, subagents, MCP tools, file attachments
- **DM + channels + threads** — @mention in channels, DM directly, reply in threads
- **Workspace context** — SOUL.md, MEMORY.md, TOOLS.md loaded per session
- **Management TUI** — switch models, change personality, manage sessions (`node manage.mjs`)
- **Zero background cost** — no process runs between messages

## Quick start

```bash
git clone https://github.com/digital-transformation-core/disclaude.git
cd disclaude
npm install
bash setup.sh
```

## Running

```bash
bash setup.sh                                    # setup wizard (first time)
export $(cat .env | xargs) && node server.mjs    # manual start
npx pm2 start server.mjs --name disclaude        # with pm2
systemctl --user status disclaude                # check service (Linux)
journalctl --user -u disclaude -f                # follow logs (Linux)
```

## Requirements

- Node.js 18+ (or Bun)
- [Claude Code CLI](https://www.npmjs.com/package/@anthropic-ai/claude-code) installed and authenticated
- [Discord bot token](https://discord.com/developers/applications) with **Message Content Intent** enabled
- Anthropic subscription (Pro/Max)

## How it works

```
You (Discord) → server.mjs → claude -p → Anthropic API → streamed response → Discord
```

Each message spawns `claude -p --model opus` — the exact same binary you use in your terminal. First message creates a session, subsequent messages use `--resume`. Claude exits after each response — zero processes between messages.

## Configuration

`.env` (created by setup):
```
DISCORD_TOKEN=your_bot_token
DISCORD_ALLOWED_USER=your_discord_id
CLAUDE_MODEL=opus
WORKSPACE=~/.disclaude/workspace
SYSTEM_PROMPT_NAME=Claude
```

Workspace files in `~/.disclaude/workspace/`: `SOUL.md` (personality), `MEMORY.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`. Per-channel context via `CHANNEL-<name>.md` or `channels/<name>/` directory.

## OpenClaw migration

`bash setup.sh` detects OpenClaw and offers to migrate — copies token, workspace, sessions, and MCP servers. **OpenClaw config is never modified.** You can switch back anytime:

```bash
systemctl --user stop disclaude && systemctl --user start claude-gateway   # switch to OpenClaw
systemctl --user stop claude-gateway && systemctl --user start disclaude   # switch to Disclaude
node manage.mjs  # select "Uninstall & revert to OpenClaw"                # full revert
```

<details>
<summary><strong>What does NOT migrate from OpenClaw</strong></summary>

| Feature | Why | Workaround |
|---------|-----|------------|
| memory-enhanced plugin | OpenClaw framework plugin | Use [claude-mem](https://github.com/thedotmack/claude-mem) (works automatically) |
| Browser plugin | OpenClaw-managed browser | Built-in `WebFetch`/`WebSearch`, or configure a browser MCP server |
| Cron / scheduled tasks | Caused rate-limiting | Not planned |
| Heartbeat / watchdog | Caused rate-limiting | Not planned |
| MCP loopback server | Gateway-managed tools | Use Claude CLI built-in tools + MCP servers in `~/.claude/settings.json` |
| Multi-channel routing | Discord/Telegram/Slack/etc. | Discord-only for now |
| Plugin hooks | Framework-specific | Modify `server.mjs` directly |

**What works natively:** Claude CLI plugins (claude-mem etc.), MCP servers, all Claude Code tools (Bash, Read, Write, Edit, WebSearch, subagents), session persistence, CLAUDE.md project rules.

</details>

## Limitations

- One message at a time per channel (different channels work in parallel)
- Streaming updates every ~900ms (Discord API rate limit, not ours)
- Single-user design (one `DISCORD_ALLOWED_USER`)

## Roadmap

| Feature | Status |
|---------|--------|
| Telegram, Slack, WhatsApp, Signal, Matrix | `soon` |
| Multi-user sessions | `planned` |
| Voice message transcription | `planned` |
| Conversation export | `planned` |

## FAQ

<details>
<summary><strong>Why did I get rate-limited with OpenClaw?</strong></summary>

OpenClaw spawns automated background sessions (cron, heartbeat, watchdog) — many `claude -p` calls per hour. Anthropic flags this as third-party usage. Disclaude only runs when you send a message. Same CLI, same auth — without the automation overhead.
</details>

<details>
<summary><strong>Bot shows "Thinking..." but never responds?</strong></summary>

Check logs: `journalctl --user -u disclaude -f`. Common causes: not authenticated (`claude auth login`), model rate-limited (switch model via `node manage.mjs`), workspace too large (files truncated to 8KB).
</details>

<details>
<summary><strong>Can I use non-Anthropic models?</strong></summary>

Yes. `node manage.mjs` → Switch model → Ollama, DeepSeek, OpenAI, Google, or custom model ID.
</details>

## License

MIT
