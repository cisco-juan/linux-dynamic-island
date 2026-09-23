#!/usr/bin/env bash
#
# List the pages and custom widgets the Dynamic Island offers.
#
set -euo pipefail

IFACE="io.github.cisco_juan.DynamicIsland"
PATH_OBJ="/Island"

echo "Pages:"
busctl --user call "$IFACE" "$PATH_OBJ" "$IFACE" ListPages

echo
echo "Widgets:"
busctl --user call "$IFACE" "$PATH_OBJ" "$IFACE" ListWidgets
