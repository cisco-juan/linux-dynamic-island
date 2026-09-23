#!/usr/bin/env bash
#
# Expand, collapse or toggle the Dynamic Island over D-Bus.
#
# Usage: ./expand-collapse.sh [expand|collapse|toggle]
#
set -euo pipefail

IFACE="io.github.cisco_juan.DynamicIsland"
PATH_OBJ="/Island"
ACTION="${1:-toggle}"

case "$ACTION" in
    expand)   METHOD="Expand" ;;
    collapse) METHOD="Collapse" ;;
    toggle)   METHOD="Toggle" ;;
    *)
        echo "Usage: $0 [expand|collapse|toggle]" >&2
        exit 2
        ;;
esac

busctl --user call "$IFACE" "$PATH_OBJ" "$IFACE" "$METHOD"

# Read the state back so the effect is visible.
busctl --user get-property "$IFACE" "$PATH_OBJ" "$IFACE" expanded
