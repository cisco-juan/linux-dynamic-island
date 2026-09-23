#!/usr/bin/env bash
#
# Show a card on the Dynamic Island over D-Bus.
#
# Usage: ./show-card.sh [app] [title] [body] [icon] [urgency] [timeoutMs]
#
set -euo pipefail

IFACE="io.github.cisco_juan.DynamicIsland"
PATH_OBJ="/Island"

APP="${1:-Example App}"
TITLE="${2:-Hello from D-Bus}"
BODY="${3:-This card was shown by examples/dbus/show-card.sh.}"
ICON="${4:-dialog-information}"
URGENCY="${5:-1}"
TIMEOUT_MS="${6:-4000}"

# ShowCard(appName, title, body, icon, urgency, timeoutMs) -> id
busctl --user call "$IFACE" "$PATH_OBJ" "$IFACE" ShowCard \
    ssssii "$APP" "$TITLE" "$BODY" "$ICON" "$URGENCY" "$TIMEOUT_MS"

echo "Card requested (the returned value above is the card id)."
