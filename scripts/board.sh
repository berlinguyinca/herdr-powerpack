#!/usr/bin/env bash
# board.sh — Powerpack capability/health board (opened as a Herdr popup pane).
# Prints the matrix, then keeps the pane open until the user presses Enter.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

bash "$HERE/doctor.sh"
echo
read -r -p "  press Enter to close the board" _ 2>/dev/null || true
exit 0
