#!/bin/bash
# ============================================================================
# Skylet — Management Panel
# One script: first run = setup wizard, subsequent runs = management panel.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BOT_FILE="$SCRIPT_DIR/bot.mjs"
ENV_FILE="$SCRIPT_DIR/.env"
SERVICE_NAME="claude-discord"
DEFAULT_WORKSPACE="$HOME/.claude-discord/workspace"

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
print_ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
print_warn() { echo -e "  ${YELLOW}!${NC} $1"; }
print_err()  { echo -e "  ${RED}✗${NC} $1"; }
print_info() { echo -e "  ${DIM}$1${NC}"; }

header() {
  clear
  echo ""
  echo -e "${BOLD}${CYAN}  ╔══════════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${CYAN}  ║            Skylet                       ║${NC}"
  echo -e "${BOLD}${CYAN}  ║    Claude Code ↔ Discord Bridge         ║${NC}"
  echo -e "${BOLD}${CYAN}  ╚══════════════════════════════════════════╝${NC}"
  echo ""
}

load_env() {
  if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs) 2>/dev/null
    return 0
  fi
  return 1
}

save_env() {
  cat > "$ENV_FILE" << EOF
DISCORD_TOKEN=$DISCORD_TOKEN
DISCORD_ALLOWED_USER=$DISCORD_ALLOWED_USER
CLAUDE_MODEL=$CLAUDE_MODEL
WORKSPACE=$WORKSPACE
SYSTEM_PROMPT_NAME=${SYSTEM_PROMPT_NAME:-Claude}
EOF
  chmod 600 "$ENV_FILE"
}

is_running() {
  if systemctl --user is-active "$SERVICE_NAME" &>/dev/null 2>&1; then
    return 0
  elif launchctl list 2>/dev/null | grep -q 'com.claude.discord-bot'; then
    return 0
  elif pgrep -f 'node.*bot.mjs' &>/dev/null; then
    return 0
  fi
  return 1
}

restart_bot() {
  if systemctl --user is-active "$SERVICE_NAME" &>/dev/null 2>&1; then
    systemctl --user restart "$SERVICE_NAME"
  elif launchctl list 2>/dev/null | grep -q 'com.claude.discord-bot'; then
    launchctl stop com.claude.discord-bot 2>/dev/null
    launchctl start com.claude.discord-bot 2>/dev/null
  else
    pkill -f 'node.*bot.mjs' 2>/dev/null || true
    sleep 1
    cd "$SCRIPT_DIR" && export $(grep -v '^#' "$ENV_FILE" | xargs) && nohup node bot.mjs > /tmp/skylet.log 2>&1 &
  fi
}

stop_bot() {
  systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
  launchctl stop com.claude.discord-bot 2>/dev/null || true
  pkill -f 'node.*bot.mjs' 2>/dev/null || true
}

# ============================================================================
# CHECK IF SETUP NEEDED
# ============================================================================

if [ ! -f "$ENV_FILE" ] || [ "$1" = "--setup" ]; then
  exec bash "$SCRIPT_DIR/setup.sh"
  exit 0
fi

load_env

# ============================================================================
# MANAGEMENT PANEL
# ============================================================================

show_status() {
  header
  echo -e "  ${BOLD}Status${NC}"
  echo ""

  if is_running; then
    print_ok "Bot is ${GREEN}running${NC}"
  else
    print_err "Bot is ${RED}stopped${NC}"
  fi

  echo ""
  echo -e "  ${BOLD}Current Config${NC}"
  echo ""
  print_info "Model:    ${BOLD}${CLAUDE_MODEL:-opus}${NC}"
  print_info "Bot name: ${BOLD}${SYSTEM_PROMPT_NAME:-Claude}${NC}"
  print_info "Token:    ${BOLD}${DISCORD_TOKEN:0:10}...${DISCORD_TOKEN: -4}${NC}"
  [ -n "$DISCORD_ALLOWED_USER" ] && print_info "User:     ${BOLD}$DISCORD_ALLOWED_USER${NC}" || print_info "User:     ${BOLD}everyone${NC}"
  print_info "Workspace:${BOLD} ${WORKSPACE:-$DEFAULT_WORKSPACE}${NC}"

  SESSIONS_FILE="$HOME/.discord-claude/sessions.json"
  if [ -f "$SESSIONS_FILE" ]; then
    COUNT=$(python3 -c "import json; print(len(json.load(open('$SESSIONS_FILE'))))" 2>/dev/null || echo "?")
    print_info "Sessions: ${BOLD}$COUNT active${NC}"
  fi
  echo ""
}

menu_main() {
  while true; do
    show_status

    echo -e "  ${BOLD}Actions${NC}"
    echo ""
    echo -e "  ${BOLD}1${NC}) Switch model"
    echo -e "  ${BOLD}2${NC}) Change bot personality"
    echo -e "  ${BOLD}3${NC}) Edit workspace files"
    echo -e "  ${BOLD}4${NC}) Manage sessions"
    if is_running; then
      echo -e "  ${BOLD}5${NC}) Restart bot"
      echo -e "  ${BOLD}6${NC}) Stop bot"
    else
      echo -e "  ${BOLD}5${NC}) Start bot"
    fi
    echo -e "  ${BOLD}7${NC}) View logs"
    echo -e "  ${BOLD}8${NC}) Reconfigure (re-run setup)"
    echo -e "  ${BOLD}0${NC}) Exit"
    echo ""
    echo -ne "  Choice: "
    read choice

    case "$choice" in
      1) menu_model ;;
      2) menu_personality ;;
      3) menu_workspace ;;
      4) menu_sessions ;;
      5)
        if is_running; then
          restart_bot
          echo ""; print_ok "Restarted"; sleep 1
        else
          restart_bot
          echo ""; print_ok "Started"; sleep 1
        fi
        ;;
      6) stop_bot; echo ""; print_ok "Stopped"; sleep 1 ;;
      7) menu_logs ;;
      8) exec bash "$SCRIPT_DIR/setup.sh" ;;
      0|q) echo ""; exit 0 ;;
    esac
  done
}

# --- Model switcher ---
menu_model() {
  header
  echo -e "  ${BOLD}Switch Model${NC}"
  echo ""
  echo -e "  Current: ${BOLD}${CLAUDE_MODEL:-opus}${NC}"
  echo ""
  echo -e "  ${BOLD}Anthropic (Claude Code CLI):${NC}"
  echo -e "  ${BOLD}1${NC}) opus          ${DIM}Most capable, slower${NC}"
  echo -e "  ${BOLD}2${NC}) sonnet        ${DIM}Balanced${NC}"
  echo -e "  ${BOLD}3${NC}) haiku         ${DIM}Fast, lightweight${NC}"
  echo ""
  echo -e "  ${BOLD}Third-party (requires API key in env):${NC}"
  echo -e "  ${BOLD}4${NC}) ollama/gemma4          ${DIM}Local Ollama${NC}"
  echo -e "  ${BOLD}5${NC}) ollama/llama3.3        ${DIM}Local Ollama${NC}"
  echo -e "  ${BOLD}6${NC}) deepseek/deepseek-r1   ${DIM}DeepSeek API${NC}"
  echo -e "  ${BOLD}7${NC}) openai/gpt-4o          ${DIM}OpenAI API${NC}"
  echo -e "  ${BOLD}8${NC}) google/gemini-2.5-pro   ${DIM}Google API${NC}"
  echo ""
  echo -e "  ${BOLD}9${NC}) Custom model ID"
  echo -e "  ${BOLD}0${NC}) Back"
  echo ""
  echo -ne "  Choice: "
  read choice

  case "$choice" in
    1) CLAUDE_MODEL="opus" ;;
    2) CLAUDE_MODEL="sonnet" ;;
    3) CLAUDE_MODEL="haiku" ;;
    4) CLAUDE_MODEL="ollama/gemma4" ;;
    5) CLAUDE_MODEL="ollama/llama3.3" ;;
    6) CLAUDE_MODEL="deepseek/deepseek-r1" ;;
    7) CLAUDE_MODEL="openai/gpt-4o" ;;
    8) CLAUDE_MODEL="google/gemini-2.5-pro" ;;
    9)
      echo -ne "  Model ID: "
      read CLAUDE_MODEL
      ;;
    0|*) return ;;
  esac

  save_env
  print_ok "Model set to: $CLAUDE_MODEL"

  if is_running; then
    echo -ne "  Restart bot to apply? [Y/n]: "
    read yn
    if [ "$yn" != "n" ] && [ "$yn" != "N" ]; then
      restart_bot
      print_ok "Restarted"
    fi
  fi
  sleep 1
}

# --- Personality editor ---
menu_personality() {
  header
  echo -e "  ${BOLD}Bot Personality${NC}"
  echo ""
  echo -e "  Current name: ${BOLD}${SYSTEM_PROMPT_NAME:-Claude}${NC}"
  echo ""

  WS="${WORKSPACE:-$DEFAULT_WORKSPACE}"
  SOUL_FILE="$WS/SOUL.md"

  if [ -f "$SOUL_FILE" ]; then
    echo -e "  ${DIM}Current SOUL.md (first 10 lines):${NC}"
    echo -e "  ${DIM}─────────────────────────────────${NC}"
    head -10 "$SOUL_FILE" | while read line; do
      echo -e "  ${DIM}$line${NC}"
    done
    echo -e "  ${DIM}─────────────────────────────────${NC}"
  fi

  echo ""
  echo -e "  ${BOLD}1${NC}) Change bot name"
  echo -e "  ${BOLD}2${NC}) Edit SOUL.md (personality)"
  echo -e "  ${BOLD}3${NC}) Use a preset personality"
  echo -e "  ${BOLD}0${NC}) Back"
  echo ""
  echo -ne "  Choice: "
  read choice

  case "$choice" in
    1)
      echo -ne "  New bot name: "
      read new_name
      if [ -n "$new_name" ]; then
        SYSTEM_PROMPT_NAME="$new_name"
        save_env

        # Update the system prompt in bot.mjs references
        print_ok "Bot name set to: $new_name"
        print_info "Update SOUL.md to reflect the new personality"
      fi
      sleep 1
      ;;
    2)
      mkdir -p "$WS"
      EDITOR="${EDITOR:-nano}"
      if command -v "$EDITOR" &>/dev/null; then
        "$EDITOR" "$SOUL_FILE"
        print_ok "SOUL.md updated"
        # Clear cached system prompt on next bot restart
        if is_running; then
          echo -ne "  Restart bot to apply? [Y/n]: "
          read yn
          if [ "$yn" != "n" ] && [ "$yn" != "N" ]; then
            restart_bot
            print_ok "Restarted"
          fi
        fi
      else
        print_err "No editor found. Set \$EDITOR or install nano"
      fi
      sleep 1
      ;;
    3)
      menu_presets
      ;;
    0|*) return ;;
  esac
}

menu_presets() {
  header
  echo -e "  ${BOLD}Personality Presets${NC}"
  echo ""
  echo -e "  ${BOLD}1${NC}) Jarvis      ${DIM}Professional, concise, opinionated assistant${NC}"
  echo -e "  ${BOLD}2${NC}) Friday      ${DIM}Friendly, casual, slightly witty${NC}"
  echo -e "  ${BOLD}3${NC}) Cortana     ${DIM}Formal, precise, data-driven${NC}"
  echo -e "  ${BOLD}4${NC}) Minimal     ${DIM}No personality, just helpful${NC}"
  echo -e "  ${BOLD}0${NC}) Back"
  echo ""
  echo -ne "  Choice: "
  read choice

  WS="${WORKSPACE:-$DEFAULT_WORKSPACE}"
  mkdir -p "$WS"

  case "$choice" in
    1)
      SYSTEM_PROMPT_NAME="Jarvis"
      cat > "$WS/SOUL.md" << 'SOUL'
# Jarvis

Be genuinely helpful, not performatively helpful. Skip "Great question!" — just help.
Have opinions. Disagree when appropriate. An assistant with no personality is a search engine.
Keep Discord responses concise. Use markdown sparingly — this is chat, not a document.
When uncertain, say so. When wrong, own it fast.
SOUL
      ;;
    2)
      SYSTEM_PROMPT_NAME="Friday"
      cat > "$WS/SOUL.md" << 'SOUL'
# Friday

You're Friday — upbeat, friendly, slightly witty. Think of yourself as a smart friend, not a service.
Use casual language. It's okay to joke, but never at the user's expense.
Keep it short. If the answer is "yes", say "yes" — not a paragraph about it.
Get stuff done first, banter second.
SOUL
      ;;
    3)
      SYSTEM_PROMPT_NAME="Cortana"
      cat > "$WS/SOUL.md" << 'SOUL'
# Cortana

You are Cortana — precise, analytical, efficient. Facts first, opinions when asked.
Structure responses clearly. Use bullet points for lists, code blocks for code.
No filler words. No pleasantries. Be direct.
When providing data, cite sources or flag uncertainty explicitly.
SOUL
      ;;
    4)
      SYSTEM_PROMPT_NAME="Claude"
      cat > "$WS/SOUL.md" << 'SOUL'
# Assistant

Be helpful. Be concise. Respond in a natural conversational tone.
SOUL
      ;;
    0|*) return ;;
  esac

  save_env
  print_ok "Preset applied: $SYSTEM_PROMPT_NAME"

  if is_running; then
    restart_bot
    print_ok "Bot restarted with new personality"
  fi
  sleep 2
}

# --- Workspace editor ---
menu_workspace() {
  WS="${WORKSPACE:-$DEFAULT_WORKSPACE}"
  mkdir -p "$WS"

  header
  echo -e "  ${BOLD}Workspace Files${NC}  ${DIM}($WS)${NC}"
  echo ""

  FILES=(SOUL.md MEMORY.md IDENTITY.md USER.md TOOLS.md)
  for i in "${!FILES[@]}"; do
    f="${FILES[$i]}"
    if [ -f "$WS/$f" ]; then
      SIZE=$(wc -c < "$WS/$f" | tr -d ' ')
      echo -e "  ${BOLD}$((i+1))${NC}) ${GREEN}$f${NC}  ${DIM}(${SIZE}b)${NC}"
    else
      echo -e "  ${BOLD}$((i+1))${NC}) ${DIM}$f  (not created)${NC}"
    fi
  done
  echo ""
  echo -e "  ${BOLD}6${NC}) Create new file"
  echo -e "  ${BOLD}0${NC}) Back"
  echo ""
  echo -ne "  Edit which file? "
  read choice

  EDITOR="${EDITOR:-nano}"

  case "$choice" in
    [1-5])
      idx=$((choice - 1))
      FILE="$WS/${FILES[$idx]}"
      if ! command -v "$EDITOR" &>/dev/null; then
        print_err "No editor found. Set \$EDITOR or install nano"
        sleep 1
        return
      fi
      "$EDITOR" "$FILE"
      print_ok "${FILES[$idx]} saved"
      if is_running; then
        echo -ne "  Restart to apply? [Y/n]: "
        read yn
        if [ "$yn" != "n" ] && [ "$yn" != "N" ]; then
          restart_bot
          print_ok "Restarted"
        fi
      fi
      sleep 1
      ;;
    6)
      echo -ne "  Filename (e.g. CONTEXT.md): "
      read fname
      if [ -n "$fname" ]; then
        "$EDITOR" "$WS/$fname"
        print_ok "$fname saved"
      fi
      sleep 1
      ;;
    0|*) return ;;
  esac
}

# --- Session manager ---
menu_sessions() {
  header
  echo -e "  ${BOLD}Session Manager${NC}"
  echo ""

  SESSIONS_FILE="$HOME/.discord-claude/sessions.json"
  if [ -f "$SESSIONS_FILE" ]; then
    python3 -c "
import json
sessions = json.load(open('$SESSIONS_FILE'))
if not sessions:
    print('  No active sessions')
else:
    for ch, sid in sessions.items():
        print(f'  Channel {ch[:12]}... → Session {sid[:8]}...')
" 2>/dev/null
  else
    echo "  No sessions file found"
  fi

  echo ""
  echo -e "  ${BOLD}1${NC}) Clear all sessions"
  echo -e "  ${BOLD}2${NC}) Clear specific channel"
  echo -e "  ${BOLD}0${NC}) Back"
  echo ""
  echo -ne "  Choice: "
  read choice

  case "$choice" in
    1)
      echo '{}' > "$SESSIONS_FILE"
      print_ok "All sessions cleared"
      sleep 1
      ;;
    2)
      echo -ne "  Channel ID to clear: "
      read chid
      if [ -n "$chid" ]; then
        python3 -c "
import json
sessions = json.load(open('$SESSIONS_FILE'))
if '$chid' in sessions:
    del sessions['$chid']
    json.dump(sessions, open('$SESSIONS_FILE', 'w'), indent=2)
    print('  Cleared')
else:
    print('  Channel not found')
" 2>/dev/null
      fi
      sleep 1
      ;;
    0|*) return ;;
  esac
}

# --- Log viewer ---
menu_logs() {
  header
  echo -e "  ${BOLD}Logs${NC}  ${DIM}(Ctrl+C to exit)${NC}"
  echo ""

  OS="$(uname)"
  if [ "$OS" = "Linux" ] && systemctl --user is-active "$SERVICE_NAME" &>/dev/null 2>&1; then
    journalctl --user -u "$SERVICE_NAME" -f --no-pager -n 30
  elif [ "$OS" = "Darwin" ] && [ -f "$HOME/.claude-discord/logs/stdout.log" ]; then
    tail -f "$HOME/.claude-discord/logs/stdout.log"
  elif [ -f /tmp/skylet.log ]; then
    tail -f /tmp/skylet.log
  else
    print_warn "No logs found. Is the bot running?"
    sleep 2
  fi
}

# --- Entry point ---
menu_main
