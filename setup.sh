#!/bin/bash
# ============================================================================
# Disclaude — Interactive Setup
# ============================================================================
#
# MIGRATION NOTICE (OpenClaw users):
# This setup can copy your existing Discord bot token and workspace files
# from OpenClaw. Your OpenClaw configuration is READ-ONLY — nothing is
# modified or deleted. The setup will:
#
#   1. Copy Discord bot token from ~/.openclaw/openclaw.json
#   2. Copy workspace files (SOUL.md, MEMORY.md, etc.) to ~/.disclaude/
#   3. ASK before stopping OpenClaw (you must confirm)
#   4. Show how to switch back to OpenClaw at any time
#   5. Show how to fully uninstall Disclaude and revert
#
# OpenClaw and Disclaude share the same Discord bot token, so only one
# can be active at a time. But switching between them is a single command.
#
# For fresh installs without OpenClaw, the setup guides you through
# creating a Discord bot step by step.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_FILE="$SCRIPT_DIR/server.mjs"
ENV_FILE="$SCRIPT_DIR/.env"
SERVICE_NAME="disclaude"
DEFAULT_WORKSPACE="$HOME/.disclaude/workspace"
OPENCLAW_CONFIG="$HOME/.openclaw/openclaw.json"
OPENCLAW_WORKSPACE="$HOME/.openclaw/workspace"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Helpers ---
print_header() {
  clear
  echo ""
  echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}  ║         Disclaude Setup                 ║${NC}"
  echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════╝${NC}"
  echo ""
}

print_step() {
  echo -e "  ${BLUE}[$1/$TOTAL_STEPS]${NC} ${BOLD}$2${NC}"
}

print_ok() {
  echo -e "       ${GREEN}✓${NC} $1"
}

print_warn() {
  echo -e "       ${YELLOW}!${NC} $1"
}

print_err() {
  echo -e "       ${RED}✗${NC} $1"
}

print_info() {
  echo -e "       ${DIM}$1${NC}"
}

prompt_input() {
  local prompt="$1"
  local var_name="$2"
  local default="$3"
  if [ -n "$default" ]; then
    echo -ne "       ${prompt} ${DIM}[$default]${NC}: "
    read input
    eval "$var_name=\"${input:-$default}\""
  else
    echo -ne "       ${prompt}: "
    read input
    eval "$var_name=\"$input\""
  fi
}

prompt_secret() {
  local prompt="$1"
  local var_name="$2"
  echo -ne "       ${prompt}: "
  read -s input
  echo ""
  eval "$var_name=\"$input\""
}

prompt_choice() {
  local prompt="$1"
  local var_name="$2"
  shift 2
  local options=("$@")
  echo ""
  for i in "${!options[@]}"; do
    echo -e "       ${BOLD}$((i+1))${NC}) ${options[$i]}"
  done
  echo ""
  echo -ne "       ${prompt} [1-${#options[@]}]: "
  read choice
  eval "$var_name=\"$choice\""
}

# --- Detect existing setup ---
detect_openclaw() {
  if [ ! -f "$OPENCLAW_CONFIG" ]; then
    return 1
  fi
  OC_TOKEN=$(python3 -c "
import json
try:
    cfg = json.load(open('$OPENCLAW_CONFIG'))
    print(cfg.get('channels',{}).get('discord',{}).get('token',''))
except: pass
" 2>/dev/null)
  [ -n "$OC_TOKEN" ]
}

extract_openclaw_config() {
  OC_TOKEN=$(python3 -c "
import json
try:
    cfg = json.load(open('$OPENCLAW_CONFIG'))
    print(cfg.get('channels',{}).get('discord',{}).get('token',''))
except: pass
" 2>/dev/null)

  OC_ALLOWED_USER=$(python3 -c "
import json
try:
    cfg = json.load(open('$OPENCLAW_CONFIG'))
    allow = cfg.get('channels',{}).get('discord',{}).get('allowFrom',[])
    if allow: print(str(allow[0]))
except: pass
" 2>/dev/null)

  OC_MODEL=$(python3 -c "
import json
try:
    cfg = json.load(open('$OPENCLAW_CONFIG'))
    m = cfg.get('agents',{}).get('defaults',{}).get('model',{}).get('primary','')
    m = m.split('/')[-1] if '/' in m else m
    aliases = {'claude-opus-4-6':'opus','claude-sonnet-4-6':'sonnet','claude-haiku-4-5':'haiku'}
    print(aliases.get(m, m or 'opus'))
except: print('opus')
" 2>/dev/null)
}

# ============================================================================
# MAIN SETUP FLOW
# ============================================================================

print_header
TOTAL_STEPS=6

# --- Step 1: Check requirements ---
print_step 1 "Checking requirements..."

MISSING=0

# Node.js 18+
if command -v node &> /dev/null; then
  NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_VER" -ge 18 ] 2>/dev/null; then
    print_ok "Node.js $(node -v)"
  else
    print_err "Node.js $(node -v) — version 18+ required"
    MISSING=1
  fi
else
  print_err "Node.js not found — install from https://nodejs.org (v18+)"
  MISSING=1
fi

# npm
if command -v npm &> /dev/null; then
  print_ok "npm $(npm -v)"
else
  print_err "npm not found — comes with Node.js"
  MISSING=1
fi

# Claude Code CLI
if command -v claude &> /dev/null; then
  CLAUDE_VERSION=$(claude --version 2>&1 | head -1)
  print_ok "Claude Code CLI ($CLAUDE_VERSION)"

  AUTH=$(claude auth status 2>&1 | grep -o '"loggedIn": true' || true)
  if [ -n "$AUTH" ]; then
    print_ok "Claude authenticated"
  else
    print_warn "Claude not logged in — run 'claude auth login' after setup"
  fi
else
  print_err "Claude Code CLI not found"
  echo ""
  echo -e "       Install: ${BOLD}npm install -g @anthropic-ai/claude-code${NC}"
  echo -e "       Then:    ${BOLD}claude auth login${NC}"
  MISSING=1
fi

# python3 (needed for OpenClaw config parsing)
if command -v python3 &> /dev/null; then
  print_ok "Python3 $(python3 --version 2>&1 | cut -d' ' -f2)"
else
  print_warn "Python3 not found — OpenClaw migration will be unavailable"
fi

# systemd user session (Linux)
if [ "$(uname)" = "Linux" ]; then
  if systemctl --user status 2>/dev/null | head -1 | grep -q 'running\|degraded'; then
    print_ok "systemd user session active"
  else
    print_warn "systemd user session not active — bot will run in foreground only"
  fi
  mkdir -p "$HOME/.config/systemd/user" 2>/dev/null
elif [ "$(uname)" = "Darwin" ]; then
  print_info "macOS detected — will use launchd (or run in foreground)"
fi

# Git (optional, for cloning)
if command -v git &> /dev/null; then
  print_ok "git $(git --version | cut -d' ' -f3)"
else
  print_info "git not found (optional)"
fi

if [ "$MISSING" -gt 0 ]; then
  echo ""
  print_err "Missing required dependencies. Install them and re-run setup."
  exit 1
fi

echo ""

# --- Step 2: Detect environment ---
print_step 2 "Detecting environment..."

HAS_OPENCLAW=false
HAS_EXISTING_ENV=false
DISCORD_TOKEN=""
ALLOWED_USER=""
CLAUDE_MODEL="opus"
WORKSPACE="$DEFAULT_WORKSPACE"

if [ -f "$ENV_FILE" ]; then
  HAS_EXISTING_ENV=true
  print_ok "Found existing .env config"
  source "$ENV_FILE" 2>/dev/null || true
  prompt_choice "Existing config found. What would you like to do?" EXISTING_CHOICE \
    "Keep current config and continue" \
    "Reconfigure from scratch"
  if [ "$EXISTING_CHOICE" = "2" ]; then
    HAS_EXISTING_ENV=false
    DISCORD_TOKEN=""
  fi
fi

if [ "$HAS_EXISTING_ENV" = false ]; then
  if detect_openclaw; then
    HAS_OPENCLAW=true
    print_ok "Found OpenClaw installation with Discord config"
    echo ""
    echo -e "       ${DIM}OpenClaw config: $OPENCLAW_CONFIG${NC}"
    echo -e "       ${DIM}This will READ (not modify) your OpenClaw config to copy${NC}"
    echo -e "       ${DIM}the Discord token and workspace files.${NC}"

    prompt_choice "How would you like to set up?" SETUP_CHOICE \
      "Migrate from OpenClaw (copy token & workspace)" \
      "Fresh setup (enter Discord token manually)"
  else
    print_info "No OpenClaw installation found"
    SETUP_CHOICE="2"
  fi
fi

echo ""

# --- Step 2: Configure Discord connection ---
print_step 3 "Configuring Discord connection..."

if [ "$HAS_EXISTING_ENV" = true ]; then
  print_ok "Using existing config"
  print_info "Token: ${DISCORD_TOKEN:0:10}...${DISCORD_TOKEN: -4}"
  [ -n "$DISCORD_ALLOWED_USER" ] && ALLOWED_USER="$DISCORD_ALLOWED_USER"
  [ -n "$CLAUDE_MODEL" ] || CLAUDE_MODEL="opus"

elif [ "$SETUP_CHOICE" = "1" ]; then
  # Migrate from OpenClaw
  extract_openclaw_config
  DISCORD_TOKEN="$OC_TOKEN"
  ALLOWED_USER="$OC_ALLOWED_USER"
  CLAUDE_MODEL="$OC_MODEL"
  print_ok "Copied Discord token from OpenClaw (${#DISCORD_TOKEN} chars)"
  [ -n "$ALLOWED_USER" ] && print_ok "Allowed user: $ALLOWED_USER"
  print_ok "Model: $CLAUDE_MODEL"

else
  # Fresh setup — guide the user
  echo ""
  echo -e "       ${BOLD}To create a Discord bot:${NC}"
  echo ""
  echo -e "       1. Go to ${CYAN}https://discord.com/developers/applications${NC}"
  echo -e "       2. Click ${BOLD}New Application${NC} → name it (e.g. \"Claude\")"
  echo -e "       3. Go to ${BOLD}Bot${NC} tab → click ${BOLD}Reset Token${NC} → copy the token"
  echo -e "       4. Enable these under ${BOLD}Privileged Gateway Intents${NC}:"
  echo -e "          ${GREEN}✓${NC} Message Content Intent"
  echo -e "          ${GREEN}✓${NC} Server Members Intent"
  echo -e "       5. Go to ${BOLD}OAuth2 → URL Generator${NC}:"
  echo -e "          Scopes: ${BOLD}bot${NC}"
  echo -e "          Permissions: ${BOLD}Send Messages, Read Message History,"
  echo -e "                       Create Public Threads, Send Messages in Threads,"
  echo -e "                       Manage Messages${NC}"
  echo -e "       6. Copy the generated URL → open it → add bot to your server"
  echo ""

  prompt_secret "Paste your Discord bot token" DISCORD_TOKEN

  if [ -z "$DISCORD_TOKEN" ]; then
    print_err "No token provided. Cannot continue."
    exit 1
  fi
  print_ok "Token set (${#DISCORD_TOKEN} chars)"

  echo ""
  echo -e "       ${DIM}Restrict the bot to only respond to you? (recommended)${NC}"
  echo -e "       ${DIM}Find your user ID: User Settings → Advanced → Developer Mode ON${NC}"
  echo -e "       ${DIM}Then right-click your name → Copy User ID${NC}"
  echo ""
  prompt_input "Your Discord user ID (leave empty to allow everyone)" ALLOWED_USER ""
  [ -n "$ALLOWED_USER" ] && print_ok "Restricted to user: $ALLOWED_USER" || print_warn "Bot will respond to everyone"

  prompt_choice "Select model" MODEL_CHOICE \
    "Opus (most capable, slower)" \
    "Sonnet (balanced, faster)" \
    "Haiku (fastest, lightweight)"
  case "$MODEL_CHOICE" in
    1) CLAUDE_MODEL="opus" ;;
    2) CLAUDE_MODEL="sonnet" ;;
    3) CLAUDE_MODEL="haiku" ;;
    *) CLAUDE_MODEL="opus" ;;
  esac
  print_ok "Model: $CLAUDE_MODEL"
fi

echo ""

# --- Step 3: Set up workspace ---
print_step 4 "Setting up workspace & sessions..."

if [ "$SETUP_CHOICE" = "1" ] && [ -d "$OPENCLAW_WORKSPACE" ]; then
  # Use OpenClaw workspace directly — no copying, same files, same Claude project dir
  WORKSPACE="$OPENCLAW_WORKSPACE"
  print_ok "Using existing OpenClaw workspace: $WORKSPACE"
  print_info "Same workspace = same Claude CLI session storage (conversations continue)"

  # Migrate session mappings: OpenClaw channel→session → Disclaude channel→session
  OC_SESSIONS="$HOME/.openclaw/agents/jarvis/sessions/sessions.json"
  if [ -f "$OC_SESSIONS" ]; then
    SESSIONS_DIR="$HOME/.disclaude"
    mkdir -p "$SESSIONS_DIR"
    MIGRATED=$(python3 -c "
import json, os, glob

oc = json.load(open('$OC_SESSIONS'))
project_dir = os.path.expanduser('~/.claude/projects/-home-simon--openclaw-workspace')
existing_files = set()
for f in glob.glob(f'{project_dir}/*.jsonl'):
    existing_files.add(os.path.basename(f).replace('.jsonl',''))

dc = {}
for key, val in oc.items():
    if not key.startswith('agent:jarvis:discord:'):
        continue
    parts = key.split(':')
    channel_id = parts[-1]
    sid = None
    if isinstance(val, dict):
        bindings = val.get('cliSessionBindings', {})
        for provider, binding in bindings.items():
            if isinstance(binding, dict) and binding.get('sessionId'):
                sid = binding['sessionId']
                break
        if not sid:
            sid = val.get('sessionId', '')
    if sid and sid in existing_files:
        dc[channel_id] = sid

json.dump(dc, open('$SESSIONS_DIR/sessions.json', 'w'), indent=2)
print(len(dc))
" 2>/dev/null)
    if [ -n "$MIGRATED" ] && [ "$MIGRATED" -gt 0 ]; then
      print_ok "Migrated $MIGRATED conversation sessions from OpenClaw"
      print_info "All existing channel conversations will continue where they left off"
    else
      print_info "No active sessions to migrate"
    fi
  fi

  # Migrate MCP servers from OpenClaw to Claude CLI project settings
  # Claude CLI reads MCP config from ~/.claude/projects/<cwd-hash>/settings.json
  MCP_MIGRATED=$(python3 -c "
import json, os

# Load OpenClaw MCP config
try:
    cfg = json.load(open('$OPENCLAW_CONFIG'))
    mcp = cfg.get('mcp', {}).get('servers', {})
    if not mcp:
        print(0)
        exit()
except:
    print(0)
    exit()

# Find the Claude CLI project settings for this workspace
workspace = '$OPENCLAW_WORKSPACE'
# Claude CLI uses path with / replaced by - and leading - stripped
project_key = workspace.replace('/', '-')
if project_key.startswith('-'):
    project_key = project_key[1:]
project_dir = os.path.expanduser(f'~/.claude/projects/{project_key}')
settings_file = os.path.join(project_dir, 'settings.json')

os.makedirs(project_dir, exist_ok=True)

# Load existing project settings
try:
    settings = json.load(open(settings_file))
except:
    settings = {}

existing_mcp = settings.get('mcpServers', {})
added = 0

for name, server in mcp.items():
    if name in existing_mcp:
        continue
    # Convert OpenClaw MCP format to Claude CLI format
    entry = {}
    if server.get('command'):
        entry['command'] = server['command']
    if server.get('args'):
        entry['args'] = server['args']
    if server.get('env'):
        entry['env'] = server['env']
    if server.get('url'):
        entry['url'] = server['url']
    if not server.get('enabled', True):
        entry['disabled'] = True
    if entry:
        existing_mcp[name] = entry
        added += 1

if added > 0:
    settings['mcpServers'] = existing_mcp
    json.dump(settings, open(settings_file, 'w'), indent=2)

print(added)
" 2>/dev/null)
  if [ -n "$MCP_MIGRATED" ] && [ "$MCP_MIGRATED" -gt 0 ]; then
    print_ok "Migrated $MCP_MIGRATED MCP tool servers from OpenClaw"
  fi
else
  # Fresh setup — create new workspace
  WORKSPACE="$DEFAULT_WORKSPACE"
  mkdir -p "$WORKSPACE"
  if [ ! -f "$WORKSPACE/SOUL.md" ]; then
    cat > "$WORKSPACE/SOUL.md" << 'SOUL'
# SOUL.md — Bot Personality

Be genuinely helpful, not performatively helpful.
Skip filler phrases — just help.
Keep Discord responses concise and conversational.
SOUL
    print_ok "Created workspace with default SOUL.md"
  else
    print_info "Workspace already exists: $WORKSPACE"
  fi
fi

echo ""

# --- Step 4: Write config & install deps ---
print_step 5 "Writing config & installing dependencies..."

cat > "$ENV_FILE" << EOF
DISCORD_TOKEN=$DISCORD_TOKEN
DISCORD_ALLOWED_USER=$ALLOWED_USER
CLAUDE_MODEL=$CLAUDE_MODEL
WORKSPACE=$WORKSPACE
SYSTEM_PROMPT_NAME=${SYSTEM_PROMPT_NAME:-Claude}
EOF
chmod 600 "$ENV_FILE"
print_ok "Wrote .env (permissions: 600)"

cd "$SCRIPT_DIR"
if [ ! -d "node_modules" ] || [ ! -d "node_modules/discord.js" ]; then
  npm install --silent 2>&1 | tail -1
  print_ok "Installed dependencies"
else
  print_ok "Dependencies already installed"
fi

echo ""

# --- Step 6: Install & start service ---
print_step 6 "Installing background service..."

# Check if OpenClaw is running — they share the same Discord bot token
# so they can't run at the same time
OPENCLAW_RUNNING=false
OPENCLAW_SERVICE=""
for svc in openclaw-gateway claude-gateway; do
  if systemctl --user is-active "$svc" &>/dev/null 2>&1; then
    OPENCLAW_RUNNING=true
    OPENCLAW_SERVICE="$svc"
    break
  fi
done

if [ "$OPENCLAW_RUNNING" = true ]; then
  echo ""
  echo -e "       ${YELLOW}${BOLD}OpenClaw gateway is currently running${NC} ($OPENCLAW_SERVICE)"
  echo ""
  echo -e "       ${DIM}Disclaude and OpenClaw both use the same Discord bot token,${NC}"
  echo -e "       ${DIM}so they cannot run at the same time. Only one can connect${NC}"
  echo -e "       ${DIM}to Discord with the same bot.${NC}"
  echo ""
  echo -e "       ${DIM}Your OpenClaw configuration will NOT be modified or deleted.${NC}"
  echo -e "       ${DIM}You can switch back to OpenClaw anytime by running:${NC}"
  echo -e "       ${DIM}  systemctl --user stop disclaude${NC}"
  echo -e "       ${DIM}  systemctl --user start $OPENCLAW_SERVICE${NC}"
  echo ""
  prompt_choice "Would you like to switch from OpenClaw to Disclaude?" SWITCH_CHOICE \
    "Yes — stop OpenClaw and start Disclaude" \
    "No — keep OpenClaw running (exit setup)"

  if [ "$SWITCH_CHOICE" = "2" ]; then
    echo ""
    print_ok "OpenClaw is still running. Disclaude config saved but not started."
    echo ""
    echo -e "       ${DIM}To switch later, run:${NC}"
    echo -e "       ${DIM}  systemctl --user stop $OPENCLAW_SERVICE${NC}"
    echo -e "       ${DIM}  systemctl --user start disclaude${NC}"
    echo ""
    exit 0
  fi

  # User confirmed — stop OpenClaw (but don't disable, so they can re-enable)
  systemctl --user stop "$OPENCLAW_SERVICE" 2>/dev/null
  print_ok "Stopped $OPENCLAW_SERVICE (can be re-enabled anytime)"
fi

# Stop any previous disclaude instance
pkill -f 'node server.mjs' 2>/dev/null || true
systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true

OS="$(uname)"
SERVICE_INSTALLED=false

if [ "$OS" = "Linux" ] && systemctl --user status &>/dev/null; then
  # --- Linux: systemd user service ---
  mkdir -p "$HOME/.config/systemd/user"

  cat > "$HOME/.config/systemd/user/$SERVICE_NAME.service" << EOF
[Unit]
Description=Claude Discord Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$(which node) $BOT_FILE
Restart=always
RestartSec=10
EnvironmentFile=$ENV_FILE
Environment=HOME=$HOME
Environment=PATH=$(dirname $(which claude)):$(dirname $(which node)):/usr/local/bin:/usr/bin:/bin
Environment=NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable "$SERVICE_NAME" 2>/dev/null
  systemctl --user start "$SERVICE_NAME"

  # Live verification: wait for bot to connect to Discord
  echo ""
  echo -ne "       Connecting to Discord "
  BOT_READY=false
  for i in $(seq 1 20); do
    if journalctl --user -u "$SERVICE_NAME" --no-pager -n 5 2>/dev/null | grep -q "Bot online"; then
      BOT_READY=true
      break
    fi
    echo -ne "."
    sleep 1
  done
  echo ""

  if [ "$BOT_READY" = true ]; then
    SERVICE_INSTALLED=true
    BOT_NAME=$(journalctl --user -u "$SERVICE_NAME" --no-pager -n 10 2>/dev/null | grep "Bot online" | sed 's/.*Bot online as //' | head -1)
    SESSIONS_COUNT=$(journalctl --user -u "$SERVICE_NAME" --no-pager -n 10 2>/dev/null | grep "Sessions:" | grep -oP '\d+' | head -1)
    echo ""
    print_ok "Connected to Discord as ${GREEN}${BOLD}${BOT_NAME}${NC}"
    [ -n "$SESSIONS_COUNT" ] && [ "$SESSIONS_COUNT" -gt 0 ] && print_ok "$SESSIONS_COUNT conversation sessions ready to resume"
  elif systemctl --user is-active "$SERVICE_NAME" &>/dev/null; then
    SERVICE_INSTALLED=true
    print_warn "Service is running but Discord connection is slow"
    print_info "Check logs: journalctl --user -u $SERVICE_NAME -f"
  else
    print_err "Service failed to start"
    echo -e "       Check: ${BOLD}journalctl --user -u $SERVICE_NAME --no-pager -n 20${NC}"
  fi

elif [ "$OS" = "Darwin" ]; then
  # --- macOS: launchd plist ---
  PLIST_DIR="$HOME/Library/LaunchAgents"
  PLIST_FILE="$PLIST_DIR/com.disclaude.plist"
  LOG_DIR="$HOME/.disclaude/logs"
  mkdir -p "$PLIST_DIR" "$LOG_DIR"

  # Build env vars from .env file
  ENV_KEYS=""
  while IFS='=' read -r key value; do
    [ -z "$key" ] && continue
    ENV_KEYS="$ENV_KEYS        <key>$key</key>
        <string>$value</string>
"
  done < "$ENV_FILE"

  cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.disclaude</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which node)</string>
        <string>$BOT_FILE</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>$HOME</string>
        <key>PATH</key>
        <string>$(dirname $(which claude)):$(dirname $(which node)):/usr/local/bin:/usr/bin:/bin</string>
$ENV_KEYS    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/stderr.log</string>
</dict>
</plist>
EOF

  launchctl unload "$PLIST_FILE" 2>/dev/null || true
  launchctl load "$PLIST_FILE" 2>/dev/null

  echo ""
  echo -ne "       Connecting to Discord "
  BOT_READY=false
  for i in $(seq 1 20); do
    if grep -q "Bot online" "$LOG_DIR/stdout.log" 2>/dev/null; then
      BOT_READY=true
      break
    fi
    echo -ne "."
    sleep 1
  done
  echo ""

  if [ "$BOT_READY" = true ]; then
    SERVICE_INSTALLED=true
    BOT_NAME=$(grep "Bot online" "$LOG_DIR/stdout.log" | tail -1 | sed 's/.*Bot online as //')
    print_ok "Connected to Discord as ${GREEN}${BOLD}${BOT_NAME}${NC}"
  elif launchctl list | grep -q 'com.disclaude'; then
    SERVICE_INSTALLED=true
    print_warn "Service is running but Discord connection is slow"
  else
    print_err "launchd service failed to start"
    echo -e "       Check: ${BOLD}cat $LOG_DIR/stderr.log${NC}"
  fi

else
  # --- Windows / other: no service manager ---
  print_warn "No service manager detected"
  print_info "Run manually: cd $SCRIPT_DIR && node server.mjs"
fi

echo ""

if [ "$SERVICE_INSTALLED" = true ]; then
  echo ""
  echo -e "  ${GREEN}${BOLD}════════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}${BOLD}  Setup complete! Bot is live on Discord.  ${NC}"
  echo -e "  ${GREEN}${BOLD}════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  ${BOLD}Try it now:${NC}"
  echo -e "    1. Open Discord"
  echo -e "    2. @mention your bot or DM it"
  echo -e "    3. Say something — it will respond with streaming text"
  echo ""
  echo -e "  ${BOLD}Manage later:${NC} node manage.mjs"
  echo ""

  if [ "$OS" = "Linux" ]; then
    echo -e "  ${DIM}Commands:${NC}"
    echo -e "    systemctl --user status $SERVICE_NAME     ${DIM}# status${NC}"
    echo -e "    journalctl --user -u $SERVICE_NAME -f     ${DIM}# logs${NC}"
    echo -e "    systemctl --user restart $SERVICE_NAME    ${DIM}# restart${NC}"
    echo -e "    systemctl --user stop $SERVICE_NAME       ${DIM}# stop${NC}"
  elif [ "$OS" = "Darwin" ]; then
    echo -e "  ${DIM}Commands:${NC}"
    echo -e "    launchctl list | grep claude              ${DIM}# status${NC}"
    echo -e "    tail -f ~/.disclaude/logs/stdout.log ${DIM}# logs${NC}"
    echo -e "    launchctl stop com.disclaude     ${DIM}# stop${NC}"
    echo -e "    launchctl start com.disclaude    ${DIM}# start${NC}"
  fi

  if [ -n "$OPENCLAW_SERVICE" ]; then
    echo ""
    echo -e "  ${DIM}Switch back to OpenClaw:${NC}"
    echo -e "    systemctl --user stop $SERVICE_NAME"
    echo -e "    systemctl --user start $OPENCLAW_SERVICE"
  fi

  echo ""
  echo -e "  ${DIM}Uninstall Disclaude and revert to OpenClaw:${NC}"
  echo -e "    systemctl --user stop $SERVICE_NAME"
  echo -e "    systemctl --user disable $SERVICE_NAME"
  echo -e "    rm ~/.config/systemd/user/$SERVICE_NAME.service"
  echo -e "    systemctl --user daemon-reload"
  [ -n "$OPENCLAW_SERVICE" ] && echo -e "    systemctl --user enable --now $OPENCLAW_SERVICE"

  echo ""
  echo -e "  ${DIM}Config:    $ENV_FILE${NC}"
  echo -e "  ${DIM}Workspace: $WORKSPACE${NC}"
  echo -e "  ${DIM}Sessions:  ~/.disclaude/sessions.json${NC}"
  echo ""
else
  echo -e "  ${YELLOW}${BOLD}════════════════════════════════════════════${NC}"
  echo -e "  ${YELLOW}${BOLD}  Setup complete — run manually${NC}"
  echo -e "  ${YELLOW}${BOLD}════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  Start the bot:"
  echo -e "    ${BOLD}cd $SCRIPT_DIR${NC}"
  echo -e "    ${BOLD}export \$(cat .env | xargs) && node server.mjs${NC}"
  echo ""
  echo -e "  Or with pm2:"
  echo -e "    ${BOLD}npx pm2 start server.mjs --name disclaude${NC}"
  echo ""
  echo -e "  ${DIM}Config:    $ENV_FILE${NC}"
  echo -e "  ${DIM}Workspace: $WORKSPACE${NC}"
  echo ""
fi
