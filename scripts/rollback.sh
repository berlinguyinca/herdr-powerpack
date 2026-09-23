#!/usr/bin/env bash
# rollback.sh — restore the last known-good snapshot.
# For every dep that was installed/up-to-date in the snapshot, force-reinstall it at
# its SNAPSHOT ref (which may differ from the current lock ref). This makes rollback
# meaningful even when the lock itself changed: you return to the exact prior revisions.
# Snapshot dep objects lack install_prereqs/platforms (lock-only fields), so we merge
# the lock's dep object and override its ref with the snapshotted ref.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"
pp_ensure_dirs

snap="$(jq -r '.last_snapshot // empty' "$PP_STATE_FILE" 2>/dev/null)"
[ -z "$snap" ] && snap="$(ls -1t "$PP_STATE_DIR/snapshots"/*.json 2>/dev/null | head -1)"
if [ -z "$snap" ] || [ ! -f "$snap" ]; then
  pp_warn "no snapshot to roll back to"; exit 1
fi
pp_info "rolling back to snapshot: $snap"

results=""
while IFS= read -r d; do
  [ -z "$d" ] && continue
  st=$(jq -r '.status // empty' <<<"$d")
  { [ "$st" = "installed" ] || [ "$st" = "up-to-date" ]; } || continue
  id=$(jq -r '.id' <<<"$d"); sref=$(jq -r '.ref // empty' <<<"$d")
  # merge the lock's dep object (for install_prereqs/platforms/etc.) and override ref
  depobj=$(jq -c --arg id "$id" --arg sref "$sref" \
    '(.dependencies[] | select(.id==$id)) | (if $sref != "" then .ref=$sref else . end)' "$PP_LOCK_FILE" 2>/dev/null)
  [ -z "$depobj" ] && { pp_warn "no lock entry for $id; skipping"; continue; }
  obj=$(pp_process_dep "$depobj" 1 2>/dev/null)
  [ -n "$obj" ] && results="${results}${obj}"$'\n'
  pp_info "rollback: $id @ $(jq -r '.installed_ref // .ref // "n/a"' <<<"$obj" 2>/dev/null | cut -c1-12)"
done < <(jq -c '.deps[]' "$snap")

pp_write_state "$results" rollback
pp_info "rollback complete"
exit 0
