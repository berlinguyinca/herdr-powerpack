#!/usr/bin/env bash
# reconcile.sh — Powerpack reconcile.
#   --light  (default): startup hook. Verifies which locked deps are currently
#            present in `herdr plugin list`, refreshes state. NO network, NO
#            reinstall. Must be fast and side-effect free (runs at server start).
#   --full   : reconcile action. Self-heals: reinstalls any default (or
#            enabled) dep that is currently missing, at its pinned ref.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

MODE="${1:---light}"
pp_ensure_dirs

# Re-detect env cheaply (no gh auth network call in --light)
detect_env_fast() {
  if [ ! -f "$PP_ENV_FILE" ]; then
    local os arch herdrver
    os="$(pp_os)"; arch="$(pp_arch)"; herdrver="$(pp_herdr_version)"
    if pp_have_jq; then
      jq -cn --arg os "$os" --arg arch "$arch" --arg herdr "$herdrver" \
        --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{os:$os,arch:$arch,herdr_version:$herdr,generated:$generated}' > "$PP_ENV_FILE"
    fi
  fi
}
detect_env_fast

if [ "$MODE" = "--full" ]; then
  # Self-heal: process all deps (pp_process_dep reinstalls missing default/enabled ones).
  dep=""; results=""; obj=""
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    obj="$(pp_process_dep "$dep" 2>/dev/null)"
    [ -n "$obj" ] && results="${results}${obj}"$'\n'
  done < <(pp_lock_deps)
  pp_write_state "$results" full
  pp_info "reconcile --full complete"
  exit 0
fi

# --light: presence check only (no install)
light() {
  local dep results="" id def hold
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    id=$(jq -r '.id' <<<"$dep")
    def=$(jq -r '.default // false' <<<"$dep")
    hold=$(jq -r '.hold // false' <<<"$dep")
    local status reason="" iref=""
    if [ "$hold" = "true" ]; then status="held"; reason="held-pending-upstream"
    elif ! pp_selected "$id" "$def" "$hold"; then status="skipped"; reason="not-selected"
    elif pp_is_installed "$id"; then status="present"; iref="$(pp_state_ref "$id")"
    else status="absent"; reason="not installed"
    fi
    local name cap repo src ref ver
    name=$(jq -r '.name // empty' <<<"$dep"); cap=$(jq -r '.capability // empty' <<<"$dep")
    repo=$(jq -r '.repo // empty' <<<"$dep"); ref=$(jq -r '.ref // empty' <<<"$dep")
    ver=$(jq -r '.version // empty' <<<"$dep")
    src="$repo"; local sub; sub=$(jq -r '.subdir // empty' <<<"$dep"); [ -n "$sub" ] && src="$repo/$sub"
    results="${results}$(_pp_dep_json "$id" "$name" "$cap" "$repo" "$src" "$ref" "$ver" "$status" "$reason" "$def" "$hold" "$iref")"$'\n'
  done < <(pp_lock_deps)
  pp_write_state "$results" light
}
light
exit 0
