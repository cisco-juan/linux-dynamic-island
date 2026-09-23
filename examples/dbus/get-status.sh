#!/usr/bin/env bash
#
# Print the Dynamic Island status as a D-Bus dictionary.
#
set -euo pipefail

IFACE="io.github.cisco_juan.DynamicIsland"
PATH_OBJ="/Island"

busctl --user call "$IFACE" "$PATH_OBJ" "$IFACE" GetStatus
