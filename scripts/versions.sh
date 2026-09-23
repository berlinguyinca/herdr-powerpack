#!/usr/bin/env bash
# versions.sh — Powerpack + managed dependency versions (locked vs installed).
#   --json for machine-readable output.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"
pp_ensure_dirs
JSON=0; [ "${1:-}" = "--json" ] && JSON=1
live_json="[]"
pp_herdr >/dev/null 2>&1 && live_json="$(pp_herdr_cli plugin list --json 2>/dev/null | jq -c '((.result.plugins // .plugins // (if type=="array" then . else [] end)))' 2>/dev/null || printf '[]')"

if [ "$JSON" = "1" ]; then
  pp_have_jq || { printf 'jq required\n' >&2; exit 2; }
  jq -cn \
    --arg powerpack "${PP_POWERPACK_VERSION:-0.1.0}" \
    --arg herdr "$(pp_herdr_version)" \
    --argjson lock "$(jq -c '{version:.powerpack.version, min_herdr:.powerpack.min_herdr_version, deps:[.dependencies[]|{id,version,ref}]}' "$PP_LOCK_FILE" 2>/dev/null || printf '{deps:[]}')" \
    --argjson live "$live_json" \
    '{powerpack:$powerpack,herdr:$herdr,lock:$lock,installed:$live}'
  exit 0
fi

echo "Powerpack ${PP_POWERPACK_VERSION:-0.1.0} (herdr $(pp_herdr_version))"
echo "  ID                              LOCKED     INSTALLED  REF(locked)"
while IFS= read -r dep; do
  [ -z "$dep" ] && continue
  id=$(jq -r '.id' <<<"$dep"); ver=$(jq -r '.version // "?"' <<<"$dep"); ref=$(jq -r '.ref // ""' <<<"$dep")
  inst=$(printf '%s' "$live_json" | jq -r --arg id "$id" 'map(select(.plugin_id?==$id or .id?==$id)) | .[0].version // "-"' 2>/dev/null)
  printf '  %-31s %-10s %-10s %s\n' "${id:0:31}" "${ver}" "${inst:--}" "${ref:0:12}"
done < <(pp_lock_deps)
exit 0
