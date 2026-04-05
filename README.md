# Skylet

Talk to [Claude Code](https://claude.com/product/claude-code) from Discord. One file, real-time streaming, persistent sessions.

<img src="https://img.shields.io/badge/Claude_Code-CLI-blue?style=flat-square" /> <img src="https://img.shields.io/badge/Discord.js-v14-5865F2?style=flat-square" /> <img src="https://img.shields.io/badge/Node.js-18+-339933?style=flat-square" />

## What it does

- **Streams responses in real-time** — watch Claude think, word by word
- **Persistent sessions** — each channel/thread remembers the full conversation
- **Full Claude Code power** — Bash, file editing, web search, subagents, MCP tools
- **Thread support** — @mention in a channel creates a thread, replies continue there
- **Workspace context** — loads your SOUL.md, MEMORY.md, TOOLS.md on first message
- **Zero background cost** — no process runs between messages

## Requirements

- [Node.js](https://nodejs.org) 18+
- [Claude Code CLI](https://www.npmjs.com/package/@anthropic-ai/claude-code) installed and authenticated
- A [Discord bot token](https://discord.com/developers/applications)

## Quick start

```bash
git clone https://github.com/user/skylet.git
cd skylet
bash setup.sh
```

The setup wizard will:
1. Check all requirements
2. Guide you through creating a Discord bot (or migrate from OpenClaw)
3. Configure your bot token and preferences
4. Install dependencies
5. Start the bot as a background service

## Manual start

```bash
npm install
export DISCORD_TOKEN=your_bot_token
export CLAUDE_MODEL=opus          # opus, sonnet, or haiku
export DISCORD_ALLOWED_USER=your_user_id  # optional
node bot.mjs
```

## How it works

Each Discord message spawns `claude -p --model opus` — the same Claude Code CLI you use in your terminal. The bot is just a bridge:

```
You (Discord) → bot.mjs → claude CLI → Anthropic API → response → Discord
```

- First message in a channel creates a new Claude session with your workspace context
- Subsequent messages use `--resume` to continue the conversation with full history
- Sessions persist on disk — pick up where you left off, days later
- Say `/new` to reset a channel's session

## Workspace

Place files in `~/.claude-discord/workspace/` to customize Claude's behavior:

| File | Purpose |
|------|---------|
| `SOUL.md` | Personality and behavior rules |
| `MEMORY.md` | Persistent memory and context |
| `IDENTITY.md` | Identity and role definition |
| `USER.md` | Info about you |
| `TOOLS.md` | Tool usage guidelines |

## Commands

| Command | What |
|---------|------|
| `@bot message` | Send a message (in channels) |
| DM the bot | Send a message (in DMs) |
| Reply in thread | Continue conversation (no @mention needed) |
| `/new` | Reset the channel's session |

## Service management

**Linux (systemd):**
```bash
systemctl --user status claude-discord
systemctl --user restart claude-discord
journalctl --user -u claude-discord -f
```

**macOS (launchd):**
```bash
launchctl list | grep claude
tail -f ~/.claude-discord/logs/stdout.log
launchctl stop com.claude.discord-bot
```

## Configuration

All config lives in `.env` (created by setup):

```
DISCORD_TOKEN=your_bot_token
DISCORD_ALLOWED_USER=your_discord_id
CLAUDE_MODEL=opus
WORKSPACE=/path/to/workspace
```

## License

MIT
