#!/usr/bin/env bash
# doctor.sh — unified Powerpack health view.
#   (default)     human-readable capability/health matrix
#   --json        machine-readable (for Ansible/CI)
#   --strict      with --json, exit 1 if any critical failure (default deps missing/failed,
#                 or an unsafe non-loopback listener).
# Never crashes: degrades gracefully. Secrets are redacted.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

JSON=0; STRICT=0
for a in "$@"; do case "$a" in --json) JSON=1;; --strict) STRICT=1;; esac; done

pp_ensure_dirs
hb="$(pp_herdr 2>/dev/null)"; hb="${hb:-herdr}"
os="$(pp_os)"; herdrver="$(pp_herdr_version)"
ghauth="false"; pp_have gh && gh auth status >/dev/null 2>&1 && ghauth="true"
chromium="false"; ( pp_have google-chrome || pp_have chromium || pp_have chromium-browser || pp_have chrome ) && chromium="true"

# Live installed plugin ids (registry read — no server socket needed)
live_json="[]"
if pp_herdr >/dev/null 2>&1; then
  live_json="$(pp_herdr_cli plugin list --json 2>/dev/null | jq -c '
      ((.result.plugins // .plugins // (if type=="array" then . else [] end)))' 2>/dev/null || printf '[]')"
fi
is_live() { printf '%s' "$live_json" | jq -e --arg id "$1" 'any(.plugin_id? == $id)' >/dev/null 2>&1; }

# Unsafe-listener scan (best-effort). Reports non-loopback listeners on web/CDP-ish ports.
unsafe_listeners() {
  local out=""
  if command -v ss >/dev/null 2>&1; then
    out="$(ss -tlnp 2>/dev/null | awk 'NR>1{print $4}')"
  elif command -v lsof >/dev/null 2>&1; then
    out="$(lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk 'NR>1{print $9}')"
  fi
  [ -z "$out" ] && return 0
  # Flag ONLY the bundle-relevant web/CDP ports when bound to a NON-loopback address.
  # (8787 = Roamgate; 9222/9229/9230 = CDP / terminal-browser.) Other listeners are
  # not the Powerpack's concern and are intentionally not reported (avoids noise).
  printf '%s\n' "$out" \
    | grep -Eiv '^(127\.0\.0\.1|\[?::1\]?)' \
    | grep -Ei ':(8787|9222|9229|9230)$' 2>/dev/null
}

# Roamgate private-by-default bind check. Reads the Powerpack-owned roamgate.env
# so we can warn on a public bind even before the service is started.
# Prints "loopback" | "exposed:<host>" | "" (roamgate not installed).
roamgate_bind() {
  local envfile="${XDG_CONFIG_HOME:-$HOME/.config}/roamgate/roamgate.env"
  [ -f "$envfile" ] || return 0
  local host; host="$(grep -E '^HOST=' "$envfile" 2>/dev/null | head -1 | cut -d= -f2-)"
  [ -n "$host" ] || return 0
  case "$host" in
    127.0.0.1|::1|localhost) echo "loopback" ;;
    *) echo "exposed:$host" ;;
  esac
}

# Build the per-dep health array
build_deps() {
  local dep id name cap repo ref ver def hold minh status reason health
  local acc=""
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    id=$(jq -r '.id' <<<"$dep"); name=$(jq -r '.name // empty' <<<"$dep")
    cap=$(jq -r '.capability // empty' <<<"$dep"); repo=$(jq -r '.repo // empty' <<<"$dep")
    ref=$(jq -r '.ref // empty' <<<"$dep"); ver=$(jq -r '.version // empty' <<<"$dep")
    def=$(jq -r '.default // false' <<<"$dep"); hold=$(jq -r '.hold // false' <<<"$dep")
    minh=$(jq -r '.min_herdr_version // empty' <<<"$dep")
    status=""; reason=""; health=""
    if [ "$hold" = "true" ]; then
      status="held"; health="held"; reason="pending upstream browser fix (see docs/upstream-audit.md)"
    elif ! pp_selected "$id" "$def" "$hold"; then
      status="optional"; health="optional"; reason="not enabled (optional)"
    elif is_live "$id"; then
      # installed -> assess health via runtime prereqs
      status="installed"; health="healthy"; reason=""
      local rp; local missingrt=""
      while IFS= read -r rp; do
        [ -z "$rp" ] && continue
        if [ "$rp" = "gh" ] && [ "$ghauth" = "false" ]; then health="degraded"; reason="gh not authenticated"; continue; fi
        if ! pp_have "$rp"; then health="degraded"; reason="${reason}${reason:+, }runtime prereq '$rp' missing"; fi
      done < <(jq -r '.runtime_prereqs // [] | .[]' <<<"$dep")
    else
      status="missing"; health="missing"
      if [ -n "$minh" ] && [ -n "$herdrver" ] && ! pp_ver_ge "$herdrver" "$minh"; then
        reason="incompatible herdr (need >=$minh, have $herdrver)"
      else
        reason="default dependency not installed (run: herdr plugin action invoke berlinguyinca.powerpack.reconcile)"
      fi
    fi
    acc="${acc}$(jq -cn --arg id "$id" --arg name "$name" --arg cap "$cap" --arg repo "$repo" \
      --arg ref "$ref" --arg ver "$ver" --arg def "$def" --arg status "$status" \
      --arg health "$health" --arg reason "$reason" \
      '{id:$id,name:$name,capability:$cap,repo:$repo,ref:$ref,version:$ver,default:$def,status:$status,health:$health,reason:$reason}')"
    acc="$acc"$'\n'
  done < <(pp_lock_deps)
  printf '%s' "$acc"
}

DEPS="$(build_deps)"

# --- machine-readable ---
if [ "$JSON" = "1" ]; then
  if pp_have_jq; then
    local_deps_json="$(printf '%s' "$DEPS" | jq -cs '.' 2>/dev/null || printf '[]')"
    listeners="$(unsafe_listeners)"
    jq -cn \
      --arg os "$os" --arg arch "$(pp_arch)" --arg herdr "$herdrver" \
      --arg powerpack "${PP_POWERPACK_VERSION:-0.1.0}" \
      --arg ghauth "$ghauth" --arg chromium "$chromium" \
      --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson deps "$local_deps_json" \
      --arg listeners "$(printf '%s' "$listeners" | jq -R . | jq -s 'map(select(length>0))')" \
      --arg roamgate_bind "$(roamgate_bind)" \
      '{ok:true,schema:1,os:$os,arch:$arch,herdr_version:$herdr,powerpack_version:$powerpack,
        gh_authenticated:($ghauth=="true"),chromium_present:($chromium=="true"),
        roamgate_bind:$roamgate_bind,
        listeners_non_loopback:$listeners,deps:$deps,generated:$generated}'
  else
    printf 'jq not available; doctor --json requires jq\n' >&2
    exit 2
  fi
  # --strict: fail on critical problems
  if [ "$STRICT" = "1" ]; then
    crit="$(printf '%s' "$DEPS" | jq -s '[.[]|select(.default=="true" and (.health=="missing" or .health=="failed"))]|length' 2>/dev/null || echo 0)"
    nlisten="$(unsafe_listeners | grep -c . || true)"
    rbind="$(roamgate_bind)"
    # A public roamgate bind (0.0.0.0 / LAN / tailnet-without-password) is a strict failure.
    exposed=0; case "$rbind" in exposed:*) exposed=1;; esac
    if [ "${crit:-0}" -gt 0 ] || [ "${nlisten:-0}" -gt 0 ] || [ "$exposed" = "1" ]; then exit 1; fi
  fi
  exit 0
fi

# --- human-readable ---
echo "HerdR Powerpack — doctor"
echo "  herdr:       ${herdrver:-unknown}   os: $os/$(pp_arch)   powerpack: ${PP_POWERPACK_VERSION:-0.1.0}"
echo "  gh auth:     $ghauth   chromium: $chromium"
echo
echo "  CAPABILITY                     STATUS     HEALTH      NOTE"
echo "  -----------------------------  ---------  ----------  -----------------------------------------"
while IFS= read -r line; do
  [ -z "$line" ] && continue
  if pp_have_jq; then
    name=$(jq -r '.name // .id' <<<"$line" | cut -c1-29)
    status=$(jq -r '.status' <<<"$line")
    health=$(jq -r '.health' <<<"$line")
    reason=$(jq -r '.reason // ""' <<<"$line")
  else
    continue
  fi
  printf '  %-30s %-10s %-11s %s\n' "$name" "$status" "$health" "$reason"
done <<<"$DEPS"
echo
RBIND="$(roamgate_bind)"
case "$RBIND" in
  loopback) echo "  ✓ roamgate bind: loopback (private)" ;;
  exposed:*) echo "  ⚠ roamgate bind: ${RBIND#exposed:} (PUBLIC) — set POWERPACK_MOBILE_BIND=loopback (or tailscale) and run reconcile" ;;
  *) : ;;
esac
LISTENERS="$(unsafe_listeners)"
if [ -n "$LISTENERS" ]; then
  echo "  ⚠ non-loopback listeners detected (review before exposing to a network):"
  printf '%s\n' "$LISTENERS" | sed 's/^/      /'
else
  echo "  ✓ no non-loopback listeners detected on common web/CDP ports"
fi
echo
echo
echo "  (run with --json for machine-readable output; --strict to fail on critical issues)"
exit 0
