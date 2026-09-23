#!/usr/bin/env bash
#
# Render the README screenshots for Dynamic Island.
#
# Runs tools/screenshots.qml fully offscreen (no Wayland session, no MPRIS, no
# dbus-monitor, no real user data) and then builds docs/screenshots/overview.png
# as a 3x2 grid of the six state images with ImageMagick.
#
# The harness loads the real components, which pull in the Island QML plugin.
# `IslandConfig` would then create a config.ini under the XDG config location,
# so every run is isolated in a throwaway XDG_CONFIG_HOME under the temp dir:
# the user's real ~/.config/dynamic-island is never read or written.
#
# Requirements: qml6, ImageMagick 7 (`magick`), and the built Island plugin
# (run `cd imports/Island && qmake6 && make` if libislandplugin.so is missing).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOTS="$HERE/docs/screenshots"
PLUGIN="$HERE/imports/Island/libislandplugin.so"
STATES=(compact media notification calendar settings customize)

if [ ! -f "$PLUGIN" ]; then
    echo "[screenshots] missing $PLUGIN" >&2
    echo "[screenshots] build it first: (cd imports/Island && qmake6 && make)" >&2
    exit 1
fi

mkdir -p "$SHOTS"

# --- isolated config + throwaway scratch -------------------------------------
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/dynamic-island-screenshots.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

export XDG_CONFIG_HOME="$SCRATCH/config"
mkdir -p "$XDG_CONFIG_HOME"
# A minimal icon theme so the Kirigami icons render offscreen.
printf '[Icons]\nTheme=breeze\n' > "$XDG_CONFIG_HOME/kdeglobals"

# --- render the six states ---------------------------------------------------
# Item.grabToImage works offscreen with the software backend, so no visible
# window and no Wayland session are needed. QT_FORCE_STDERR_LOGGING surfaces the
# harness' progress lines when stderr is not a console.
(
    cd "$HERE"
    env \
        XDG_CURRENT_DESKTOP=KDE \
        QT_QPA_PLATFORMTHEME=kde \
        QT_QPA_PLATFORM=offscreen \
        QT_QUICK_BACKEND=software \
        QT_FORCE_STDERR_LOGGING=1 \
        qml6 -I imports tools/screenshots.qml
)

# --- build the overview grid -------------------------------------------------
# Pad every state to the largest canvas so the tiles line up, then montage them
# in a 3x2 grid with small gaps. The exact combined-grid command is:
#
#   magick montage padded/compact.png padded/media.png padded/notification.png \
#       padded/calendar.png padded/settings.png padded/customize.png \
#       -tile 3x2 -geometry +16+16 -background '#E4E4EA' \
#       docs/screenshots/overview.png
#
maxw=0
maxh=0
for state in "${STATES[@]}"; do
    read -r w h < <(magick identify -format '%w %h\n' "$SHOTS/$state.png")
    if (( w > maxw )); then maxw=$w; fi
    if (( h > maxh )); then maxh=$h; fi
done

mkdir -p "$SCRATCH/padded"
padded=()
for state in "${STATES[@]}"; do
    magick "$SHOTS/$state.png" \
        -gravity center -background '#E4E4EA' -extent "${maxw}x${maxh}" \
        "$SCRATCH/padded/$state.png"
    padded+=("$SCRATCH/padded/$state.png")
done

magick montage "${padded[@]}" \
    -tile 3x2 -geometry +16+16 -background '#E4E4EA' \
    "$SHOTS/overview.png"

echo "[screenshots] wrote $SHOTS/{$(IFS=,; echo "${STATES[*]}"),overview}.png"
