#!/usr/bin/env bash
# Builds dist/claude-sessions_<version>_all.deb with dpkg-deb (no extra tools).
#
#   ./make-deb.sh            version from `git describe --tags` (or 0.0.0)
#   ./make-deb.sh 1.2.3      explicit version
#
# Maintainer field: $DEB_MAINTAINER, else git user.name/user.email, else a
# generic placeholder (CI).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(git describe --tags --always 2>/dev/null | sed -E 's/^v//; s/-([0-9]+)-g([0-9a-f]+)$/+\1.g\2/' || true)"
  [[ "$VERSION" =~ ^[0-9] ]] || VERSION="0.0.0+$(git rev-parse --short HEAD 2>/dev/null || echo local)"
fi
VERSION="${VERSION#v}"

if [[ -n "${DEB_MAINTAINER:-}" ]]; then
  MAINTAINER="$DEB_MAINTAINER"
else
  NAME="$(git config user.name 2>/dev/null || true)"
  EMAIL="$(git config user.email 2>/dev/null || true)"
  if [[ -n "$NAME" && -n "$EMAIL" ]]; then
    MAINTAINER="$NAME <$EMAIL>"
  else
    MAINTAINER="claude-sessions maintainers <noreply@users.noreply.github.com>"
  fi
fi

# Homepage: $DEB_HOMEPAGE, else the GitHub origin remote, else omitted
HOMEPAGE="${DEB_HOMEPAGE:-}"
if [[ -z "$HOMEPAGE" ]]; then
  ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
  case "$ORIGIN" in
    git@github.com:*) HOMEPAGE="https://github.com/${ORIGIN#git@github.com:}"; HOMEPAGE="${HOMEPAGE%.git}" ;;
    https://github.com/*) HOMEPAGE="${ORIGIN%.git}" ;;
  esac
fi

PKG=claude-sessions
BUILD="$(mktemp -d)"
ROOT="$BUILD/$PKG"
trap 'rm -rf "$BUILD"' EXIT

install -Dm755 claude-sessions "$ROOT/usr/bin/claude-sessions"
# Stamp the version into the executable so --version matches the package
sed -i "s/^__version__ = \".*\"/__version__ = \"$VERSION\"/" "$ROOT/usr/bin/claude-sessions"

install -Dm644 packaging/claude-sessions-indicator.desktop "$ROOT/etc/xdg/autostart/claude-sessions-indicator.desktop"
install -Dm644 packaging/claude-sessions.desktop "$ROOT/usr/share/applications/claude-sessions.desktop"
install -Dm644 README.md "$ROOT/usr/share/doc/$PKG/README.md"
install -Dm644 packaging/copyright "$ROOT/usr/share/doc/$PKG/copyright"

mkdir -p "$ROOT/DEBIAN"
cat > "$ROOT/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: python3, python3-gi, python3-gi-cairo, gir1.2-gtk-3.0, gir1.2-ayatanaappindicator3-0.1, gir1.2-rsvg-2.0, libnotify-bin
Recommends: gnome-shell-ubuntu-extensions | gnome-shell-extension-appindicator
Maintainer: $MAINTAINER
${HOMEPAGE:+Homepage: $HOMEPAGE
}Description: Claude Code session status in the GNOME top bar
 Shows one icon per open Claude Code session in the GNOME top bar (running,
 idle, waiting for you, done) and sends a desktop notification when a session
 asks a question or needs permission. Hooks are registered per user in
 ~/.claude/settings.json the first time the indicator starts, or with
 "claude-sessions setup".
EOF
# Conffiles: the autostart entry may be edited/disabled by the admin
echo "/etc/xdg/autostart/claude-sessions-indicator.desktop" > "$ROOT/DEBIAN/conffiles"

mkdir -p dist
OUT="dist/${PKG}_${VERSION}_all.deb"
dpkg-deb --build --root-owner-group "$ROOT" "$OUT" >/dev/null
echo "$OUT"
