#!/usr/bin/env bash
# Uninstalls claude-sessions: removes ONLY the hooks that point to this
# command, the autostart entry, the command and the state directory.
# apt packages are left alone.
set -euo pipefail

BIN="${HOME}/.local/bin/claude-sessions"
SETTINGS="${HOME}/.claude/settings.json"
AUTOSTART="${HOME}/.config/autostart/claude-sessions-indicator.desktop"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-sessions"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

stop_indicator() {
  local pidfile="$1/indicator.pid" pid
  [[ -r "$pidfile" ]] || return 1
  pid="$(cat "$pidfile")"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'claude-sessions indicator' || return 1
  kill "$pid" 2>/dev/null || return 1
  return 0
}
stop_indicator "$STATE_DIR" && log "Indicator stopped" || true

if [[ -x "$BIN" ]]; then
  "$BIN" unsetup | sed 's/^/    /'
  log "Hooks removed from $SETTINGS (backup kept next to it)"
fi

rm -f "$AUTOSTART" && log "Autostart entry removed"
rm -f "$BIN" && log "Command removed: $BIN"
rm -rf "$STATE_DIR" && log "State directory removed: $STATE_DIR"
log "Uninstalled. Open Claude Code sessions are not affected."
