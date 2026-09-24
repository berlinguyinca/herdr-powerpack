#!/usr/bin/env bash
# common.sh — shared helpers for the HerdR Powerpack.
# Hard dependencies: bash, git, curl. jq is used for machine-readable output.
# Everything else is optional and degrades gracefully.
#
# Sourced by bootstrap.sh / reconcile.sh / doctor.sh / board.sh / update.sh / rollback.sh.

set -o pipefail

# ---------------------------------------------------------------------------
# Paths (env-overridable so tests can isolate them; stable across build/runtime)
# ---------------------------------------------------------------------------
PP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
PP_PLUGIN_ROOT="${HERDR_PLUGIN_ROOT:-$(dirname "$PP_SCRIPT_DIR")}"
PP_LOCK_FILE="${POWERPACK_LOCK:-$PP_PLUGIN_ROOT/config/bundle.lock.json}"
PP_STATE_DIR="${POWERPACK_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr-powerpack}"
PP_CONFIG_DIR="${POWERPACK_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-powerpack}"
PP_STATE_FILE="$PP_STATE_DIR/reconcile.json"
PP_ENV_FILE="$PP_STATE_DIR/env.json"
PP_OWNERSHIP_MARKER="# managed by berlinguyinca.powerpack — do not edit by hand"
PP_POWERPACK_VERSION="${PP_POWERPACK_VERSION:-$(awk -F'"' '/^version[[:space:]]*=/{print $2; exit}' "$PP_PLUGIN_ROOT/herdr-plugin.toml" 2>/dev/null)}"
[ -n "$PP_POWERPACK_VERSION" ] || PP_POWERPACK_VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Herdr binary
# ---------------------------------------------------------------------------
pp_herdr() {
  if [ -n "${HERDR_BIN_PATH:-}" ] && [ -x "${HERDR_BIN_PATH:-/nonexistent}" ]; then
    printf '%s\n' "$HERDR_BIN_PATH"
    return 0
  fi
  command -v herdr >/dev/null 2>&1 && { printf '%s\n' "$(command -v herdr)"; return 0; }
  return 1
}

# pp_herdr_cli <args...> — run a Herdr REGISTRY op (plugin install/list/uninstall/
# enable/disable) with NO server socket. Registry ops are file-based and do not need
# a running server; unsetting the socket keeps them correct when the caller happens
# to be inside a Herdr pane (HERDR_SOCKET_PATH set) — matching how [[build]] hooks
# run (the docs guarantee build commands get no Herdr socket env).
pp_herdr_cli() {
  local hb; hb="$(pp_herdr 2>/dev/null)" || return 1
  env -u HERDR_SOCKET_PATH -u HERDR_ENV "$hb" "$@"
}

# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------
pp_os() {
  case "$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')" in
    darwin) printf 'macos' ;;
    linux)  printf 'linux' ;;
    msys*|cygwin*|windows*) printf 'windows' ;;
    *) printf 'unknown' ;;
  esac
}

pp_arch() {
  case "$(uname -m 2>/dev/null)" in
    x86_64|amd64) printf 'x86_64' ;;
    arm64|aarch64) printf 'arm64' ;;
    *) uname -m 2>/dev/null ;;
  esac
}

pp_herdr_version() {
  local hb; hb="$(pp_herdr 2>/dev/null)" || { printf ''; return 0; }
  "$hb" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1
}

# pp_ver_ge A B -> exit 0 if A >= B (semver, numeric per component)
pp_ver_ge() {
  local a="$1" b="$2"
  a="${a#v}"; b="${b#v}"
  local IFS=.
  local -a A B
  read -r -a A <<<"$a"
  read -r -a B <<<"$b"
  local i av bv
  for i in 0 1 2; do
    av="${A[i]:-0}"; bv="${B[i]:-0}"
    av="$(printf '%s' "$av" | grep -oE '^[0-9]+' || printf 0)"
    bv="$(printf '%s' "$bv" | grep -oE '^[0-9]+' || printf 0)"
    if [ "$av" -gt "$bv" ]; then return 0; fi
    if [ "$av" -lt "$bv" ]; then return 1; fi
  done
  return 0
}

pp_have() { command -v "$1" >/dev/null 2>&1; }

# Make a usable rustup environment for cargo-based deps (e.g. notifications).
# Rustup's default toolchain lives under ~/.rustup, so a redirected HOME makes
# cargo think no default is configured. Production (real HOME) needs nothing;
# this hardens odd-HOME cases and the test harness (which points RUSTUP_HOME at
# the real toolchain to simulate a host that has Rust).
pp_ensure_rustup_env() {
  [ -z "${RUSTUP_HOME:-}" ] && [ -d "$HOME/.rustup" ] && export RUSTUP_HOME="$HOME/.rustup"
  if [ -z "${RUSTUP_TOOLCHAIN:-}" ] && command -v rustup >/dev/null 2>&1; then
    local t; t="$(rustup show active-toolchain 2>/dev/null | awk '{print $1}')"
    [ -n "$t" ] && export RUSTUP_TOOLCHAIN="$t"
  fi
}

# The node's Tailscale IPv4 (best-effort; empty if tailscale absent/not up).
pp_tailscale_ip() {
  command -v tailscale >/dev/null 2>&1 || return 1
  tailscale ip -4 2>/dev/null | head -1
}

# OWN roamgate's bind so the mobile surface is PRIVATE by default. Roamgate's
# own `service install` defaults to HOST=0.0.0.0 (exposes the LAN); the Powerpack
# overrides it to loopback unless the operator opts into tailnet/LAN. This is the
# spec's "private/Tailscale-oriented binding, not a public listener" requirement.
# Ownership-aware: it sets HOST/PORT and preserves any user-set ROAMGATE_PASSWORD
# / TLS lines. Roamgate preserves an existing roamgate.env on `service install`.
pp_configure_roamgate() {
  local bind="${POWERPACK_MOBILE_BIND:-loopback}"
  local host="127.0.0.1"
  case "$bind" in
    tailscale) host="$(pp_tailscale_ip || true)"; [ -n "$host" ] || { pp_warn "tailscale bind requested but no tailnet IP found; falling back to loopback"; host="127.0.0.1"; } ;;
    lan)       host="0.0.0.0" ;;
    *)         host="127.0.0.1" ;;
  esac
  local cfgdir="${XDG_CONFIG_HOME:-$HOME/.config}/roamgate"
  local envfile="$cfgdir/roamgate.env"
  mkdir -p "$cfgdir"
  local tmp="$cfgdir/.roamgate.env.pp.$$"
  {
    # preserve user secrets/config (password, TLS) if present
    if [ -f "$envfile" ]; then
      grep -E '^(ROAMGATE_PASSWORD=|ROAMGATE_TLS_CERT=|ROAMGATE_TLS_KEY=|ROAMGATE_LOG_LEVEL=|HERDR_)' "$envfile" 2>/dev/null
    fi
    echo "# Managed by herdr-powerpack: bind is private by default (loopback)."
    echo "# Override with POWERPACK_MOBILE_BIND=loopback|tailscale|lan, then reconcile."
    echo "HOST=$host"
    echo "PORT=${POWERPACK_MOBILE_PORT:-8787}"
  } > "$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$envfile"
  pp_info "roamgate bind -> HOST=$host ($bind)"
}

# Post-install owned config for managed deps (idempotent). Currently: roamgate bind.
# Call after the reconcile/bootstrap install pass completes.
pp_configure_managed() {
  if [ "$(jq -r '[.deps[]|select(.id=="roamgate" and (.status=="installed" or .status=="up-to-date"))]|length' "$PP_STATE_FILE" 2>/dev/null)" = "1" ]; then
    pp_configure_roamgate
  fi
}

# Integration-boundary check (Phase 4). The Powerpack must NOT own a competing
# task/dispatch state machine. Cross-references the live plugins against the
# lock's 'rejected' set (by owner/repo) and flags any rejected plugin that is
# actually present. Competing-state plugins (tasks/dispatch/tasks-board) are the
# hard boundary; other rejected plugins are reported for completeness.
#   integration_check <live-json-array>
# Prints lines: "COMPETING_STATE <repo>" or "REJECTED_PRESENT <repo>".
integration_check() {
  local live_json="${1:-}" rejected live_repos repo
  rejected="$(jq -r '.rejected // [] | .[].repo' "$PP_LOCK_FILE" 2>/dev/null)"
  [ -z "$rejected" ] && return 0
  live_repos="$(printf '%s\n' "$live_json" | jq -r '.[] | select(.source.kind=="github") | "\(.source.owner)/\(.source.repo)"' 2>/dev/null)"
  [ -z "$live_repos" ] && return 0
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    if printf '%s\n' "$live_repos" | grep -qxF "$repo"; then
      case "$repo" in
        *herdr-tasks*|*herdr-dispatch*|*tasks-board*) echo "COMPETING_STATE $repo" ;;
        *) echo "REJECTED_PRESENT $repo" ;;
      esac
    fi
  done <<<"$rejected"
}

# ---------------------------------------------------------------------------
# Logging (honours POWERPACK_QUIET=1); secrets are redacted on stderr too
# ---------------------------------------------------------------------------
_pp_redact() {
  # redact common secret shapes: bearer tokens, gh_*/github_pat_*, tg bot tokens, ROAMGATE_PASSWORD=
  sed -E \
    -e 's#(ghp_[A-Za-z0-9]{8,}|gho_[A-Za-z0-9]{8,}|github_pat_[A-Za-z0-9_]{16,}|xox[bpasr]-[A-Za-z0-9-]{8,})#***REDACTED***#g' \
    -e 's#([0-9]+:[A-Za-z0-9_-]{30,}@[A-Za-z0-9_-]{6,})#***REDACTED***#g' \
    -e 's#(ROAMGATE_PASSWORD=)[^ ]*#\1***#g' \
    -e 's#(Bearer\s+)[A-Za-z0-9._-]{12,}#\1***#g'
}

# Diagnostics go to STDERR so they never pollute captured command output
# (e.g. $(pp_process_dep ...)). Only the JSON result is ever written to stdout.
_pp_log() { # level msg...
  local lvl="$1"; shift
  local line; line="$*"
  if [ "${POWERPACK_QUIET:-0}" = "1" ] && [ "$lvl" != "error" ]; then return 0; fi
  if [ "$lvl" = "error" ]; then
    printf 'powerpack: %s\n' "$(printf '%s' "$line" | _pp_redact)" >&2
  else
    printf '[powerpack:%s] %s\n' "$lvl" "$(printf '%s' "$line" | _pp_redact)" >&2
  fi
}
pp_info()  { _pp_log info "$@"; }
pp_warn()  { _pp_log warn "$@"; }
pp_error() { _pp_log error "$@"; }

# ---------------------------------------------------------------------------
# State helpers (jq required; degrade to text when absent)
# ---------------------------------------------------------------------------
pp_have_jq() { command -v jq >/dev/null 2>&1; }

pp_ensure_dirs() {
  mkdir -p "$PP_STATE_DIR" "$PP_CONFIG_DIR" 2>/dev/null || true
}

# Read a lock field for a dependency id: pp_lock_field <id> <field>
pp_lock_field() {
  local id="$1" field="$2"
  if ! pp_have_jq; then return 1; fi
  jq -r --arg id "$id" --arg f "$field" \
    '.dependencies[] | select(.id==$id) | .[$f] // empty' "$PP_LOCK_FILE" 2>/dev/null
}

# Iterate enabled-or-selected dependency ids: prints "id<TAB>json" lines
pp_lock_deps() {
  pp_have_jq || return 0
  jq -c '.dependencies[]' "$PP_LOCK_FILE" 2>/dev/null
}

# Is a plugin id currently installed (any source)? uses herdr plugin list --json
pp_is_installed() {
  local id="$1"
  pp_herdr_cli plugin list --json 2>/dev/null \
    | jq -e --arg id "$id" '
        ((.result.plugins // .plugins // (if type=="array" then . else [] end)))
        | any(.plugin_id? == $id)' >/dev/null 2>&1
}

# pp_write_state <deps-ndjson> [mode]
# Writes reconcile.json ROBUSTLY: deps come as newline-delimited JSON objects on $1,
# env is slurped from the env file. Uses --slurpfile (file-based) so JSON is never
# passed through shell --argjson quoting (which is fragile). Never fails the caller.
pp_write_state() {
  local deps_nd="${1:-}" mode="${2:-full}"
  local tmp depsfile
  tmp="$(mktemp)"; depsfile="$(mktemp)"
  printf '%s\n' "$deps_nd" | grep -v '^[[:space:]]*$' > "$tmp" 2>/dev/null || true
  jq -cs '.' "$tmp" > "$depsfile" 2>/dev/null || printf '[]' > "$depsfile"
  if [ -f "$PP_ENV_FILE" ]; then
    jq -cn --slurpfile env "$PP_ENV_FILE" --slurpfile deps "$depsfile" \
      --arg powerpack "${PP_POWERPACK_VERSION}" \
      --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg mode "$mode" \
      '{schema:1, powerpack_version:$powerpack, generated:$generated, mode:$mode, env:$env[0], deps:$deps[0]}' \
      > "$PP_STATE_FILE" 2>/dev/null
  else
    jq -cn --slurpfile deps "$depsfile" \
      --arg powerpack "${PP_POWERPACK_VERSION}" \
      --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg mode "$mode" \
      '{schema:1, powerpack_version:$powerpack, generated:$generated, mode:$mode, env:{}, deps:$deps[0]}' \
      > "$PP_STATE_FILE" 2>/dev/null
  fi
  rm -f "$tmp" "$depsfile"
  return 0
}

# ---------------------------------------------------------------------------
# Prerequisite auto-install (opt-in via POWERPACK_AUTO_PREREQS, default: on for bun)
# ---------------------------------------------------------------------------
pp_install_bun() {
  if pp_have bun; then return 0; fi
  [ "${POWERPACK_AUTO_PREREQS:-1}" = "1" ] || return 1
  pp_warn "bun not found; installing via official script (set POWERPACK_AUTO_PREREQS=0 to disable)"
  local os; os="$(pp_os)"
  if [ "$os" = "macos" ] || [ "$os" = "linux" ]; then
    curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1 && return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Selection + per-dependency processing (shared by bootstrap.sh and reconcile.sh)
# ---------------------------------------------------------------------------
pp_enabled_list_file() { printf '%s/enable.list' "$PP_CONFIG_DIR"; }

# pp_selected <id> <default> <hold> -> 0 (install) / 1 (do not install)
pp_selected() {
  local id="$1" def="$2" hold="$3"
  if [ "$hold" = "true" ]; then
    [ "${POWERPACK_FORCE:-0}" = "1" ] || return 1
  fi
  if [ -n "${POWERPACK_ONLY:-}" ]; then
    case ",${POWERPACK_ONLY}," in *",$id,"*) return 0 ;; esac
    return 1
  fi
  [ "$def" = "true" ] && return 0
  local ef; ef="$(pp_enabled_list_file)"
  if [ -f "$ef" ] && grep -qx "$id" "$ef" 2>/dev/null; then return 0; fi
  return 1
}

# pp_state_ref <id> -> ref recorded in state (empty if none)
pp_state_ref() {
  local id="$1"
  [ -f "$PP_STATE_FILE" ] || return 0
  pp_have_jq || return 0
  jq -r --arg id "$id" '.deps // [] | map(select(.id==$id)) | .[0].installed_ref // empty' "$PP_STATE_FILE" 2>/dev/null
}

# _pp_dep_json <id> <name> <cap> <repo> <src> <ref> <ver> <status> <reason> <def> <hold> <installed_ref>
_pp_dep_json() {
  jq -cn \
    --arg id "$1" --arg name "$2" --arg cap "$3" --arg repo "$4" --arg src "$5" \
    --arg ref "$6" --arg ver "$7" --arg status "$8" --arg reason "$9" --arg def "${10}" \
    --arg hold "${11}" --arg iref "${12}" \
    '{id:$id,name:$name,capability:$cap,repo:$repo,source:$src,ref:$ref,version:$ver,status:$status,reason:$reason,default:$def,hold:$hold,installed_ref:$iref}'
}

# _pp_emit_final — reads the calling pp_process_dep locals (bash dynamic scoping)
_pp_emit_final() {
  _pp_dep_json "$id" "$name" "$cap" "$repo" "$install_src" "$ref" "$ver" "$status" "$reason" "$def" "$hold" "$installed_ref"
}

# pp_process_dep <dep-json> [force] -> prints ONE JSON object; always returns 0
pp_process_dep() {
  local dep="$1" force="${2:-0}"
  local hb; hb="$(pp_herdr 2>/dev/null)" || hb=""
  local id name cap repo subdir ref ver minh os herdrver def hold install_src status reason installed_ref=""
  id=$(jq -r '.id' <<<"$dep")
  name=$(jq -r '.name // empty' <<<"$dep")
  cap=$(jq -r '.capability // empty' <<<"$dep")
  repo=$(jq -r '.repo // empty' <<<"$dep")
  subdir=$(jq -r '.subdir // empty' <<<"$dep")
  ref=$(jq -r '.ref // empty' <<<"$dep")
  ver=$(jq -r '.version // empty' <<<"$dep")
  minh=$(jq -r '.min_herdr_version // empty' <<<"$dep")
  def=$(jq -r '.default // false' <<<"$dep")
  hold=$(jq -r '.hold // false' <<<"$dep")
  os="$(pp_os)"; herdrver="$(pp_herdr_version)"
  install_src="$repo"; [ -n "$subdir" ] && install_src="$repo/$subdir"

  # 1) selection
  if ! pp_selected "$id" "$def" "$hold"; then
    if [ "$hold" = "true" ]; then status="held"; reason="held-pending-upstream (see docs/upstream-audit.md)"
    else status="skipped"; reason="not-selected"; fi
    _pp_emit_final; return 0
  fi

  # 2) platform
  local plats; plats=$(jq -r '.platforms // [] | join(",")' <<<"$dep")
  if [ -n "$plats" ]; then
    case ",$plats," in *",$os,"*) : ;; *) status="skipped"; reason="platform:$os unsupported"; _pp_emit_final; return 0 ;; esac
  fi

  # 3) herdr version compatibility
  if [ -n "$minh" ] && [ -n "$herdrver" ] && ! pp_ver_ge "$herdrver" "$minh"; then
    status="skipped"; reason="incompatible-herdr (need >=$minh, have $herdrver)"; _pp_emit_final; return 0
  fi

  # 4) install prereqs
  local p missing=""
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    if ! pp_have "$p"; then
      if [ "$p" = "bun" ] && pp_install_bun >/dev/null 2>&1 && pp_have bun; then :; else missing="$missing $p"; fi
    fi
  done < <(jq -r '.install_prereqs // [] | .[]' <<<"$dep")
  if [ -n "$missing" ]; then
    status="skipped"; reason="missing-prereq:${missing# }"; _pp_emit_final; return 0
  fi

  # 5) idempotency: already installed (and not forced) -> up-to-date, no reinstall
  if [ "$force" != "1" ] && [ -n "$hb" ] && pp_is_installed "$id"; then
    installed_ref="$(pp_state_ref "$id")"; [ -z "$installed_ref" ] && installed_ref="$ref"
    status="up-to-date"; reason="already installed"; _pp_emit_final; return 0
  fi

  # 6) install (best-effort)
  if [ -z "$hb" ]; then status="failed"; reason="herdr binary not found"; _pp_emit_final; return 0; fi
  # For cargo-based deps, ensure rustup can resolve a default toolchain.
  if jq -e '.install_hook // "" | test("cargo")' <<<"$dep" >/dev/null 2>&1; then pp_ensure_rustup_env; fi
  local out rc
  out=$(pp_herdr_cli plugin install "$install_src" --ref "$ref" -y 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    status="installed"; installed_ref="$ref"; pp_info "installed $id @ ${ref:0:12}"
  else
    status="failed"; reason="install failed: $(printf '%s' "$out" | tail -n1 | _pp_redact)"; pp_warn "install failed: $id: $reason"
  fi
  _pp_emit_final
  return 0
}
