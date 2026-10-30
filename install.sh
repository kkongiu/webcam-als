#!/usr/bin/env bash
# Installer for webcam-als.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${PREFIX:-$HOME/.local}/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
SYSTEMD="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

echo "==> installing to $BIN"
mkdir -p "$BIN" "$APPS"
install -m755 "$ROOT/src/webcam-als" "$BIN/webcam-als"
install -m755 "$ROOT/src/webcam-als-settings" "$BIN/webcam-als-settings"

echo "==> application launcher"
sed "s|@BIN@|$BIN|g" "$ROOT/packaging/webcam-als-settings.desktop" > "$APPS/webcam-als-settings.desktop"

if [ -d "$SYSTEMD" ] && [ -w "$SYSTEMD" ]; then
    echo "==> systemd user unit"
    install -m644 "$ROOT/packaging/webcam-als.service" "$SYSTEMD/webcam-als.service"
    systemctl --user daemon-reload || true
else
    echo "==> skipping systemd unit (run 'sudo chown -R \$USER: ~/.config/systemd' to enable it)"
fi

kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

echo
echo "Done. Start the settings app with: webcam-als-settings"
echo "Enable the daemon with the 'Attiva ora' checkbox."
