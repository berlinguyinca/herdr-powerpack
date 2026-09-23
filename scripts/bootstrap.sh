#!/usr/bin/env bash
# bootstrap.sh — HerdR Powerpack build hook.
# Runs during `herdr plugin install berlinguyinca/herdr-powerpack`, as the user,
# with NO server. Best-effort: it installs every dependency it can, records the
# outcome, and ALWAYS exits 0 so a per-dependency failure never aborts the
# Powerpack install (the whole point of a fault-tolerant meta-plugin).
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

pp_ensure_dirs

# ---------------------------------------------------------------------------
# 1) Environment detection -> env.json
# ---------------------------------------------------------------------------
detect_env() {
  local os arch herdrver jqavail
  os="$(pp_os)"; arch="$(pp_arch)"; herdrver="$(pp_herdr_version)"
  jqavail="false"; pp_have_jq && jqavail="true"
  local ghauth="false"
  if pp_have gh && gh auth status >/dev/null 2>&1; then ghauth="true"; fi
  local chromium="false"
  if pp_have google-chrome || pp_have chromium || pp_have chromium-browser || pp_have chrome; then chromium="true"; fi

  local tools
  tools=$(jq -cn \
    --argjson git "$(pp_have git && echo true || echo false)" \
    --argjson curl "$(pp_have curl && echo true || echo false)" \
    --argjson bun "$(pp_have bun && echo true || echo false)" \
    --argjson go "$(pp_have go && echo true || echo false)" \
    --argjson cargo "$(pp_have cargo && echo true || echo false)" \
    --argjson node "$(pp_have node && echo true || echo false)" \
    --argjson npm "$(pp_have npm && echo true || echo false)" \
    --argjson gh "$(pp_have gh && echo true || echo false)" \
    --argjson agent_browser "$(pp_have agent-browser && echo true || echo false)" \
    --argjson chafa "$(pp_have chafa && echo true || echo false)" \
    --argjson jq "$jqavail" \
    '{git:$git,curl:$curl,bun:$bun,go:$go,cargo:$cargo,node:$node,npm:$npm,gh:$gh,agent_browser:$agent_browser,chafa:$chafa,jq:$jq}')

  if pp_have_jq; then
    jq -cn \
      --arg os "$os" --arg arch "$arch" --arg herdr "$herdrver" \
      --arg ghauth "$ghauth" --arg chromium "$chromium" \
      --argjson tools "$tools" \
      --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{os:$os,arch:$arch,herdr_version:$herdr,gh_authenticated:$ghauth,chromium_present:$chromium,tools:$tools,generated:$generated}' \
      > "$PP_ENV_FILE"
  else
    printf 'os=%s arch=%s herdr=%s gh_auth=%s chromium=%s tools=%s\n' \
      "$os" "$arch" "$herdrver" "$ghauth" "$chromium" "$tools" > "$PP_ENV_FILE"
  fi
  pp_info "env: os=$os arch=$arch herdr=$herdrver gh_auth=$ghauth bun=$(pp_have bun && echo yes || echo no)"
}

# ---------------------------------------------------------------------------
# 2) Ownership-aware Powerpack-owned config (idempotent; never touches user config)
# ---------------------------------------------------------------------------
write_owned_config() {
  # Powerpack-owned defaults record (informational; the real per-dep config is
  # managed by HerdR under each dep's HERDR_PLUGIN_CONFIG_DIR).
  cat > "$PP_CONFIG_DIR/powerpack.defaults" <<EOF
$PP_OWNERSHIP_MARKER
# Written by bootstrap.sh; regenerated idempotently on every reconcile.
# Optional (non-default) capabilities you want enabled — one plugin id per line,
# uncomment to enable. The 'reconcile' action re-applies this list.
#   zenbu-labs.terminal-browser
#   barnuri.herdr-notifications
#   official.plannotator        # HOLD — see docs/upstream-audit.md
EOF
  # Persistent enable list (only lines present are honoured).
  local ef; ef="$(pp_enabled_list_file)"
  if [ ! -f "$ef" ]; then printf '%s\n' "$PP_OWNERSHIP_MARKER" > "$ef"; fi
  chmod 600 "$PP_CONFIG_DIR/powerpack.defaults" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 3) Process every locked dependency (best-effort)
# ---------------------------------------------------------------------------
run() {
  local dep results="" obj
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    obj="$(pp_process_dep "$dep" 2>/dev/null)"
    [ -n "$obj" ] && results="${results}${obj}"$'\n'
  done < <(pp_lock_deps)
  pp_write_state "$results" full
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
detect_env
write_owned_config
run

if pp_have_jq && [ -f "$PP_STATE_FILE" ]; then
  local_ok=0
  installed=$(jq -r '[.deps[]|select(.status=="installed" or .status=="up-to-date")]|length' "$PP_STATE_FILE" 2>/dev/null || echo 0)
  skipped=$(jq -r '[.deps[]|select(.status=="skipped")]|length' "$PP_STATE_FILE" 2>/dev/null || echo 0)
  failed=$(jq -r '[.deps[]|select(.status=="failed")]|length' "$PP_STATE_FILE" 2>/dev/null || echo 0)
  pp_info "bootstrap complete: installed/up-to-date=$installed skipped=$skipped failed=$failed"
fi

# Always succeed: a per-dependency failure must not abort the Powerpack install.
exit 0
