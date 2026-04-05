#!/bin/bash
# ============================================================================
# Claude Discord Bot — Interactive Setup
# ============================================================================
#
# MIGRATION NOTICE:
# If you previously used OpenClaw, this setup can automatically migrate your
# existing Discord bot token and workspace files. Your OpenClaw configuration
# at ~/.openclaw/openclaw.json will be read (NOT modified or deleted) to
# extract:
#   - Discord bot token (channels.discord.token)
#   - Allowed user IDs (channels.discord.allowFrom)
#   - Model preference (agents.defaults.model.primary)
#   - Workspace files (SOUL.md, MEMORY.md, etc. from ~/.openclaw/workspace/)
#
# No OpenClaw files are modified or removed. You can run both side-by-side
# or fully switch — your choice.
#
# For fresh installs without OpenClaw, the setup will guide you through
# creating a Discord bot and connecting it step by step.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_FILE="$SCRIPT_DIR/bot.mjs"
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
print_step 4 "Setting up workspace..."
WORKSPACE="${WORKSPACE:-$DEFAULT_WORKSPACE}"
mkdir -p "$WORKSPACE"

if [ "$SETUP_CHOICE" = "1" ] && [ -d "$OPENCLAW_WORKSPACE" ]; then
  COPIED=0
  for f in SOUL.md MEMORY.md IDENTITY.md USER.md TOOLS.md AGENTS.md; do
    if [ -f "$OPENCLAW_WORKSPACE/$f" ] && [ ! -f "$WORKSPACE/$f" ]; then
      cp "$OPENCLAW_WORKSPACE/$f" "$WORKSPACE/$f"
      print_ok "Copied $f from OpenClaw"
      COPIED=$((COPIED + 1))
    fi
  done
  [ $COPIED -eq 0 ] && print_info "Workspace files already present"
else
  if [ ! -f "$WORKSPACE/SOUL.md" ]; then
    cat > "$WORKSPACE/SOUL.md" << 'SOUL'
# SOUL.md — Bot Personality

Be genuinely helpful, not performatively helpful.
Skip filler phrases — just help.
Keep Discord responses concise and conversational.
SOUL
    print_ok "Created default SOUL.md"
  else
    print_info "SOUL.md already exists"
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

# Stop old services (best-effort)
pkill -f 'node bot.mjs' 2>/dev/null || true
systemctl --user stop openclaw-gateway 2>/dev/null && print_info "Stopped openclaw-gateway" || true
systemctl --user stop claude-gateway 2>/dev/null && print_info "Stopped claude-gateway" || true
systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
systemctl --user disable openclaw-gateway 2>/dev/null || true
systemctl --user disable claude-gateway 2>/dev/null || true

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
  sleep 3

  if systemctl --user is-active "$SERVICE_NAME" &>/dev/null; then
    SERVICE_INSTALLED=true
    print_ok "systemd service installed and started"
  else
    print_err "systemd service failed to start"
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

  sleep 3
  if launchctl list | grep -q 'com.disclaude'; then
    SERVICE_INSTALLED=true
    print_ok "launchd service installed and started"
  else
    print_err "launchd service failed to start"
    echo -e "       Check: ${BOLD}cat $LOG_DIR/stderr.log${NC}"
  fi

else
  # --- Windows / other: no service manager ---
  print_warn "No service manager detected"
  print_info "Run manually: cd $SCRIPT_DIR && node bot.mjs"
fi

echo ""

if [ "$SERVICE_INSTALLED" = true ]; then
  echo -e "  ${GREEN}${BOLD}════════════════════════════════════════════${NC}"
  echo -e "  ${GREEN}${BOLD}  Bot is running!${NC}"
  echo -e "  ${GREEN}${BOLD}════════════════════════════════════════════${NC}"
  echo ""
  echo -e "  Mention ${BOLD}@${NC}your-bot in Discord or DM it to start chatting."
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
  echo -e "    ${BOLD}export \$(cat .env | xargs) && node bot.mjs${NC}"
  echo ""
  echo -e "  Or with pm2:"
  echo -e "    ${BOLD}npx pm2 start bot.mjs --name disclaude${NC}"
  echo ""
  echo -e "  ${DIM}Config:    $ENV_FILE${NC}"
  echo -e "  ${DIM}Workspace: $WORKSPACE${NC}"
  echo ""
fi
