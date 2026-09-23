#!/usr/bin/env bash
#
# Development runner for Dynamic Island.
#
# Builds the C++ QML plugin (imports/Island) in-place when needed, then starts
# the overlay with the Wayland QPA platform. Safe to run repeatedly.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$HERE/imports/Island"
PLUGIN_SO="$PLUGIN_DIR/libislandplugin.so"

# Build the plugin when it is missing or older than any of its sources.
needs_build=0
if [ -f "$PLUGIN_DIR/Island.pro" ]; then
    if [ ! -f "$PLUGIN_SO" ]; then
        needs_build=1
    else
        for src in "$PLUGIN_DIR"/*.cpp "$PLUGIN_DIR"/*.h "$PLUGIN_DIR/Island.pro"; do
            [ -f "$src" ] || continue
            if [ "$src" -nt "$PLUGIN_SO" ]; then
                needs_build=1
                break
            fi
        done
    fi
fi

if [ "$needs_build" -eq 1 ]; then
    echo "[dynamic-island] building Island QML plugin..." >&2
    ( cd "$PLUGIN_DIR" && qmake6 && make -j"$(nproc)" ) >&2
fi

# Layer-shell requires a Wayland QPA; force it even if the session var is unset.
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"

qml6 -I "$HERE/imports" "$HERE/main.qml" &
QML_PID=$!

# qml6 spawns a `dbus-monitor` child. Kill both so no orphan is left behind
# when the runner is stopped (Ctrl+C, SIGTERM, or `kill <pid>`).
cleanup() {
    # Kill the dbus-monitor child while qml6 still exists as its parent,
    # then stop qml6 itself.
    pkill -P "$QML_PID" 2>/dev/null || true
    kill "$QML_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

wait "$QML_PID"
