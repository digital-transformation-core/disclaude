# Disclaude

**Talk to Claude Code from Discord.** One file. Real-time streaming. Persistent sessions. Full tool access.

<img src="https://img.shields.io/badge/Claude_Code-CLI-blue?style=flat-square" /> <img src="https://img.shields.io/badge/Discord.js-v14-5865F2?style=flat-square" /> <img src="https://img.shields.io/badge/Node.js-18+-339933?style=flat-square" />

> **Purpose:** Disclaude exists for one reason — to let you use your existing Anthropic subscription (Pro/Max) from Discord instead of a terminal window. That's it. It runs the official `claude` CLI binary with your own authenticated session. No API key spoofing, no rate limit circumvention, no request manipulation, no header forging, no multi-accounting, no credential sharing, no automated session farming, no background polling. **Every API call is a genuine, human-initiated Claude Code CLI invocation — identical to you typing in a terminal.** This project does not bypass, exploit, or abuse any Anthropic service. It is a personal convenience tool for paying subscribers who want to access what they already paid for through a different interface.

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
| Manage the bot | `node manage.mjs` (or `bun manage.mjs`) |

## Management panel

```bash
node manage.mjs
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
You (Discord) → server.mjs → claude -p → Anthropic API → streamed response → Discord
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
- **Discord rate limits streaming** — message edits are capped at ~5/5s by Discord's API, so streaming updates every ~900ms
- **No multi-user support** — designed for single-user personal use (one `DISCORD_ALLOWED_USER`)

### What does NOT migrate from OpenClaw

If you're coming from OpenClaw, the setup migrates your Discord token, workspace, sessions, and MCP tool servers automatically. However, these OpenClaw-specific features have no equivalent in the native Claude CLI and are **not available** in Disclaude:

| Feature | Why it doesn't migrate | Workaround |
|---------|----------------------|------------|
| **memory-enhanced plugin** | OpenClaw framework plugin, not a Claude CLI plugin. Handles observation DB, short-term memory, thread summarization, insight extraction. | Use [claude-mem](https://github.com/thedotmack/claude-mem) (Claude CLI plugin) — it provides `save_memory`, `search`, `get_observations` and works automatically with Disclaude. |
| **Browser plugin** | OpenClaw-managed headless browser with dedicated control server. | Claude CLI has built-in `WebFetch` and `WebSearch` tools. For full browser control, configure a browser MCP server. |
| **Cron / scheduled tasks** | Intentionally excluded — automated background sessions caused Anthropic rate-limiting. | Not planned. Use system cron to send messages via Discord API if needed. |
| **Heartbeat / watchdog polling** | Automated health checks that spawned sessions every 30 min. | Not planned — this was the primary cause of rate-limit flags. |
| **MCP loopback server** | OpenClaw's gateway-managed tool server (sessions_send, sessions_list, subagents, image_generate, etc.). | Claude CLI has built-in subagent support. Other tools available via MCP servers you configure in `~/.claude/settings.json`. |
| **Multi-channel routing** | OpenClaw routed messages across Discord, Telegram, Slack, etc. simultaneously. | Disclaude is Discord-only for now. Other channels on the roadmap. |
| **Auto-reply / delivery system** | Smart reply queuing, delivery retry, typing TTL management. | Disclaude handles replies directly — simpler but no retry on failure. |
| **Plugin hook system** | `message_received`, `thread_closed`, `reaction_received` hooks for custom behavior. | Not available. Bot logic is in `server.mjs` — modify directly if needed. |
| **Config schema UI** | Web-based configuration panel for gateway settings. | Use `node manage.mjs` TUI panel or edit `.env` directly. |

### What DOES work natively (no migration needed)

These are Claude CLI features, not OpenClaw features — they work automatically:

- **Claude CLI plugins** (claude-mem, typescript-lsp, rust-analyzer-lsp) — loaded from `~/.claude/plugins/`
- **MCP servers** configured in `~/.claude/settings.json` — available in every session
- **All Claude Code tools** — Bash, Read, Write, Edit, Grep, Glob, WebFetch, WebSearch, Agent (subagents), etc.
- **Session persistence** — Claude CLI stores conversation history on disk, resumed via `--resume`
- **CLAUDE.md / project rules** — loaded automatically from the workspace directory

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

## FAQ

**Will Disclaude break my OpenClaw setup?**

No. Disclaude only reads your OpenClaw config to copy the Discord token and workspace files. Nothing in `~/.openclaw/` is modified or deleted. The setup will explicitly ask before stopping OpenClaw, and you can decline — your config is saved but the bot won't start until you're ready.

**Can I run both at the same time?**

No — they share the same Discord bot token, so only one can connect. But switching is one command:

```bash
# Switch to Disclaude
systemctl --user stop claude-gateway && systemctl --user start disclaude

# Switch back to OpenClaw
systemctl --user stop disclaude && systemctl --user start claude-gateway
```

**How do I fully uninstall Disclaude and go back to OpenClaw?**

Option 1 — use the management panel:
```bash
node manage.mjs
# Select "Uninstall & revert to OpenClaw"
```

Option 2 — manual:
```bash
# Stop and remove Disclaude service
systemctl --user stop disclaude
systemctl --user disable disclaude
rm ~/.config/systemd/user/disclaude.service
systemctl --user daemon-reload

# Re-enable OpenClaw
systemctl --user enable --now claude-gateway
# or: systemctl --user enable --now openclaw-gateway
```

Your Disclaude sessions and workspace stay on disk at `~/.disclaude/` until you delete them.

**Why did I get rate-limited with OpenClaw?**

OpenClaw runs automated background sessions — cron jobs, heartbeat polling, watchdog checks — that spawn many `claude -p` calls per hour. Anthropic's servers detect this volume pattern and flag it as third-party app usage, which draws from your extra usage credits instead of your plan.

Disclaude only runs when you send a message. No automation, no background sessions, no session spam. Same CLI, same auth, same model — just without the overhead that triggers the rate limit.

**Does Anthropic know this is not a terminal session?**

No. Each message runs `claude -p --model opus` — the exact same binary, auth, and flags as typing in your terminal. There's no orchestrator, no third-party header, no process spoofing. It's a genuine Claude Code CLI call, just triggered from Discord instead of your keyboard.

**My bot shows "Thinking..." but never responds**

Check the logs: `journalctl --user -u disclaude -f`. Common causes:
- Claude CLI not authenticated: run `claude auth login`
- Model rate-limited: wait a few minutes or switch to a different model via `node manage.mjs`
- Large MEMORY.md causing context overflow: the bot truncates files to 8KB but very large workspaces can still overflow

**Can I use non-Anthropic models?**

Yes. Claude Code CLI supports third-party models. Run `node manage.mjs` → Switch model → select Ollama, DeepSeek, OpenAI, Google, or enter a custom model ID. You'll need the provider's API key set in your environment.

---

## License

MIT

## Credits

Born from the frustration of getting rate-limited by orchestrator overhead. If you just want to talk to Claude from Discord without the complexity, this is it.
