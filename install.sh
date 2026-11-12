#!/usr/bin/env bash
# Installs claude-sessions: apt dependencies, the command in ~/.local/bin,
# hooks in ~/.claude/settings.json (merged, with backup) and GNOME autostart.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
BIN="${BIN_DIR}/claude-sessions"
SETTINGS="${HOME}/.claude/settings.json"
AUTOSTART_DIR="${HOME}/.config/autostart"
AUTOSTART="${AUTOSTART_DIR}/claude-sessions-indicator.desktop"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/claude-sessions"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# Stops the indicator through its pidfile (never pkill -f on loose text,
# which could kill any process whose command line mentions the name).
stop_indicator() {
  local pidfile="$1/indicator.pid" pid
  [[ -r "$pidfile" ]] || return 1
  pid="$(cat "$pidfile")"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'claude-sessions indicator' || return 1
  kill "$pid" 2>/dev/null || return 1
  sleep 0.5
  return 0
}

# 1. Dependencies -----------------------------------------------------------
PKGS=(python3 python3-gi python3-gi-cairo gir1.2-gtk-3.0 gir1.2-ayatanaappindicator3-0.1 gir1.2-rsvg-2.0 libnotify-bin)
MISSING=()
for p in "${PKGS[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if ((${#MISSING[@]})); then
  log "Installing packages: ${MISSING[*]}"
  sudo apt-get install -y "${MISSING[@]}"
else
  log "apt dependencies already installed"
fi

/usr/bin/python3 -c '
import gi
gi.require_version("Gtk", "3.0"); gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import Gtk, AyatanaAppIndicator3
' || { echo "ERROR: /usr/bin/python3 cannot import GTK/AyatanaAppIndicator3" >&2; exit 1; }

# 2. Command ---------------------------------------------------------------
mkdir -p "$BIN_DIR"
chmod +x "${REPO_DIR}/claude-sessions"
ln -sfn "${REPO_DIR}/claude-sessions" "$BIN"
log "Command installed: $BIN -> ${REPO_DIR}/claude-sessions"
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "WARNING: $BIN_DIR is not in your PATH" >&2 ;;
esac

# 3. Hooks (merged into ~/.claude/settings.json with a backup) -------------
"$BIN" setup | sed 's/^/    /'
log "Hooks registered in $SETTINGS"

# 4. Autostart --------------------------------------------------------------
mkdir -p "$AUTOSTART_DIR" "$STATE_DIR"
cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Claude Code sessions indicator
Comment=Claude Code session status in the top bar
Exec=$BIN indicator
Icon=utilities-terminal
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
OnlyShowIn=GNOME;
EOF
log "Autostart entry created: $AUTOSTART"

# 5. Start now ---------------------------------------------------------------
stop_indicator "$STATE_DIR" && log "Previous indicator stopped"
if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
  nohup "$BIN" indicator >"${STATE_DIR}/indicator.log" 2>&1 &
  disown
  log "Indicator started (log: ${STATE_DIR}/indicator.log)"
else
  log "No graphical session; the indicator will start at next login"
fi

log "Done. New Claude Code sessions (or existing ones after their next event) will show up in the bar."
echo "    Check with: claude-sessions status"
