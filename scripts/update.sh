#!/usr/bin/env bash
# update.sh — Powerpack update lifecycle (Phase 3 hardened).
#   1. snapshot the current known-good state (refs + statuses)
#   2. preflight: report intended pinned-ref changes (the lock is the source of truth)
#   3. force-refresh every selected dependency at its pinned lock ref
#   4. smoke gate: run doctor; if a default dep that was healthy regressed to
#      failed/missing, AUTOMATICALLY roll back to the snapshot
#   5. on success, record last_snapshot and accept
# Never leaves HerdR worse than the snapshot: a bad update is auto-rolled-back.
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
  cp -f "$PP_STATE_FILE" "$snap"; pp_info "snapshot -> $snap"
else
  printf '{schema:1,deps:[]}' > "$snap"; pp_warn "no prior state; empty snapshot"
fi

# 2) preflight: intended pinned-ref changes (locked ref vs previously installed ref)
if pp_have_jq; then
  changes=$(jq -rn --slurpfile cur "$snap" --slurpfile lock "$PP_LOCK_FILE" '
    ($cur[0].deps // []) as $c | ($lock[0].dependencies // []) as $l
    | [ $l[] | select((.default==true) and (.hold!=true)) as $d
        | ($c[] | select(.id==$d.id)) as $prev
        | select(($prev.ref // null) != null and ($prev.ref != $d.ref))
        | "  \($d.id): \($prev.ref[0:12]) -> \($d.ref[0:12])" ] | .[]')
  if [ -n "$changes" ]; then
    pp_info "preflight: pinned ref changes vs current install (review before accepting):"
    printf '%s\n' "$changes"
  else
    pp_info "preflight: no pinned-ref changes (re-pinning current lock)"
  fi
fi

# 3) force refresh at pinned refs
dep=""; results=""
while IFS= read -r dep; do
  [ -z "$dep" ] && continue
  obj="$(pp_process_dep "$dep" 1 2>/dev/null)"
  [ -n "$obj" ] && results="${results}${obj}"$'\n'
done < <(pp_lock_deps)
pp_write_state "$results" update

# 4) smoke gate: regressions = default deps that were healthy in the snapshot but
#    are now failed/missing after the update.
regress=0
if pp_have_jq; then
  regress=$(jq -rn --slurpfile cur "$snap" --slurpfile new "$PP_STATE_FILE" '
    ($cur[0].deps // []) as $c | ($new[0].deps // []) as $n
    | [ $c[] | select(.default=="true" and (.status=="installed" or .status=="up-to-date")) as $d
        | ($n[] | select(.id==$d.id)) as $now
        | select((($now.status // "missing")) as $s | ($s=="failed" or $s=="missing"))
        | $d.id ] | length')
fi

# 5) accept or auto-rollback
if [ "${regress:-0}" -gt 0 ]; then
  pp_warn "smoke gate: $regress default dep(s) regressed after update — auto-rolling back"
  jq -c --arg snap "$snap" '.last_snapshot=$snap' "$PP_STATE_FILE" > "$PP_STATE_FILE.tmp" 2>/dev/null && mv -f "$PP_STATE_FILE.tmp" "$PP_STATE_FILE"
  bash "$HERE/rollback.sh" 2>&1 | sed 's/^/    /'
  pp_warn "update rolled back; HerdR remains on the previous known-good set"
  exit 1
fi

if pp_have_jq && [ -f "$PP_STATE_FILE" ]; then
  jq -c --arg snap "$snap" '.last_snapshot=$snap' "$PP_STATE_FILE" > "$PP_STATE_FILE.tmp" 2>/dev/null && mv -f "$PP_STATE_FILE.tmp" "$PP_STATE_FILE"
  installed=$(jq -r '[.deps[]|select(.status=="installed")]|length' "$PP_STATE_FILE" 2>/dev/null || echo 0)
  failed=$(jq -r '[.deps[]|select(.status=="failed")]|length' "$PP_STATE_FILE" 2>/dev/null || echo 0)
  pp_info "update accepted: installed=$installed failed=$failed (snapshot: $snap)"
fi
exit 0
