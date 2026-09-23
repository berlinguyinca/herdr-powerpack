#!/usr/bin/env bash
# update.sh — Powerpack update lifecycle (basic; hardened with smoke-gate in Phase 3).
#   1. snapshot the current known-good state
#   2. force-reinstall every default/enabled dependency at its pinned lock ref
#   3. write the new reconcile state + a summary
# Rollback (rollback.sh) restores the last snapshot if an update goes bad.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"
pp_ensure_dirs
SNAP_DIR="$PP_STATE_DIR/snapshots"
mkdir -p "$SNAP_DIR"

# 1) snapshot
snap="$SNAP_DIR/$(date -u +%Y%m%dT%H%M%SZ).json"
if [ -f "$PP_STATE_FILE" ]; then
  cp -f "$PP_STATE_FILE" "$snap"
  pp_info "snapshot -> $snap"
else
  pp_warn "no prior state to snapshot (first run); creating empty snapshot"
  printf '{schema:1,deps:[]}' > "$snap"
fi

# 2) force refresh at pinned refs
dep=""; results=""
while IFS= read -r dep; do
  [ -z "$dep" ] && continue
  obj="$(pp_process_dep "$dep" 1 2>/dev/null)"
  [ -n "$obj" ] && results="${results}${obj}"$'\n'
done < <(pp_lock_deps)

pp_write_state "$results" update
if pp_have_jq && [ -n "$snap" ] && [ -f "$PP_STATE_FILE" ]; then
  jq -c --arg snap "$snap" '.last_snapshot=$snap' "$PP_STATE_FILE" > "$PP_STATE_FILE.tmp" 2>/dev/null && mv -f "$PP_STATE_FILE.tmp" "$PP_STATE_FILE"
fi
if pp_have_jq && [ -f "$PP_STATE_FILE" ]; then
  installed=$(jq -r '[.deps[]|select(.status=="installed")]|length' "$PP_STATE_FILE" 2>/dev/null || echo 0)
  failed=$(jq -r '[.deps[]|select(.status=="failed")]|length' "$PP_STATE_FILE" 2>/dev/null || echo 0)
  pp_info "update complete: installed=$installed failed=$failed (snapshot: $snap)"
fi
exit 0
