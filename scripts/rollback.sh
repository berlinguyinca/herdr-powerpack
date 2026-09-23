#!/usr/bin/env bash
# rollback.sh — restore the last known-good Powerpack snapshot (basic; hardened in Phase 3).
# Reads the most recent snapshot and re-pins each previously-installed dependency
# to the ref it recorded. Optional deps are left untouched.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"
pp_ensure_dirs
SNAP_DIR="$PP_STATE_DIR/snapshots"

snap="$(ls -1 "$SNAP_DIR"/*.json 2>/dev/null | sort | tail -n1)"
if [ -z "$snap" ] || [ ! -f "$snap" ]; then
  pp_error "no snapshot found in $SNAP_DIR; nothing to roll back to"
  exit 1
fi
pp_info "rolling back to snapshot: $snap"

if pp_have_jq; then
  # For each dep that was installed at a ref, reinstall at that ref.
  while IFS=$'\t' read -r id src ref; do
    [ -z "$id" ] && continue
    pp_info "re-pinning $id -> ${ref:0:12}"
    out="$(pp_herdr_cli plugin install "$src" --ref "$ref" -y 2>&1)"; rc=$?
    if [ $rc -eq 0 ]; then pp_info "  ok: $id"
    else pp_warn "  failed: $id: $(printf '%s' "$out" | tail -n1 | _pp_redact)"; fi
  done < <(jq -r '.deps[] | select(.installed_ref != null and .installed_ref != "" and (.status=="installed" or .status=="up-to-date" or .status=="present")) | [.id,.source,.installed_ref] | @tsv' "$snap" 2>/dev/null)
  pp_info "rollback complete"
fi
exit 0
