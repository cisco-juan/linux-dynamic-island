#!/usr/bin/env bash
#
# Autostart installer for Dynamic Island.
#
# Writes a desktop entry to ~/.config/autostart so the overlay launches with the
# KDE session. This script is intentionally NOT run automatically; run it
# yourself when you want the island to start on login.
#
set -euo pipefail

APP_NAME="dynamic-island"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/run.sh"
AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
DESKTOP_FILE="$AUTOSTART_DIR/$APP_NAME.desktop"

uninstall() {
    if [ -f "$DESKTOP_FILE" ]; then
        rm -f "$DESKTOP_FILE"
        echo "Removed $DESKTOP_FILE"
    else
        echo "Nothing to remove: $DESKTOP_FILE does not exist"
    fi
}

install() {
    if [ ! -x "$RUNNER" ]; then
        echo "Error: $RUNNER is missing or not executable." >&2
        exit 1
    fi

    mkdir -p "$AUTOSTART_DIR"

    # Quoted heredoc delimiters keep the literal body free of shell expansion,
    # and the runner path is emitted verbatim by printf so spaces or special
    # characters in the path cannot corrupt the Exec= line.
    {
        cat <<'EOF'
[Desktop Entry]
Type=Application
Name=Dynamic Island
Comment=Apple-style Dynamic Island overlay for KDE Plasma 6 (Wayland)
EOF
        printf 'Exec=%s\n' "$RUNNER"
        cat <<'EOF'
Terminal=false
StartupNotify=false
X-KDE-autostart-after=panel
OnlyShowIn=KDE;
EOF
    } > "$DESKTOP_FILE"

    echo "Installed $DESKTOP_FILE"
    echo "Dynamic Island will start with your next KDE session."
    echo "Start it now with: $RUNNER"
}

case "${1:-}" in
    --uninstall|-u)
        uninstall
        ;;
    ""|--install|-i)
        install
        ;;
    *)
        echo "Usage: $0 [--install|--uninstall]" >&2
        exit 1
        ;;
esac
