#!/usr/bin/env bash
# run-tests.sh — HerdR Powerpack acceptance test harness.
#
# Runs an ISOLATED HerdR environment (temp HOME + XDG dirs) so the real user's
# HerdR is never touched. Exercises the acceptance scenarios that can be
# validated without a live browser/phone:
#   1. clean install            2. install over existing config (preservation)
#   3. idempotency              4. graceful degradation (missing prereq)
#   5. doctor --json (machine)  6. doctor human
#   7. doctor --strict (CI)     8. HOLD deps are never auto-installed
#
# Usage:
#   tests/run-tests.sh             # fast subset (no-build + one prebuilt dep)
#   POWERPACK_TEST_DEPS="..." tests/run-tests.sh   # override the dep set
#   tests/run-tests.sh --keep      # keep the temp HOME for debugging
#
# Exit code: 0 if all tests pass, 1 otherwise.
set -o pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT="$(dirname "$HERE")"
KEEP=0; [ "${1:-}" = "--keep" ] && KEEP=1

# Default fast subset: 3 no-build deps + 1 prebuilt-download dep + roamgate
# (to exercise the missing-prereq degrade path). Override with POWERPACK_TEST_DEPS.
DEPS="${POWERPACK_TEST_DEPS:-structupath.swarm,serhii-chernenko.worktreeinclude,structupath.browser,roamgate,jonasbaeumer.file-annotator}"

TESTHOME="$(mktemp -d "${TMPDIR:-/tmp}/pp-test.XXXXXX")"
export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_DATA_HOME="$TESTHOME/.local/share"
export XDG_CACHE_HOME="$TESTHOME/.cache"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export POWERPACK_AUTO_PREREQS=0   # hermetic: never auto-install bun in tests
export POWERPACK_ONLY="$DEPS"
STATE="$XDG_STATE_HOME/herdr-powerpack/reconcile.json"

PASS=0; FAIL=0; FAILED_NAMES=""
ok()   { PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES="$FAILED_NAMES $1"; printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
# assert <name> <command...>  — runs the command (output suppressed); ok iff rc 0
assert() { local name="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name"; fi; }
reset_state() { rm -rf "$XDG_STATE_HOME/herdr-powerpack"; }
state_field() { jq -r "$1" "$STATE" 2>/dev/null; }

echo "HerdR Powerpack — acceptance tests"
echo "  isolated HOME: $TESTHOME"
echo "  deps under test: $DEPS"
echo

# --- Test 1: clean install -------------------------------------------------
echo "[1] clean install"
reset_state
bash "$ROOT/scripts/bootstrap.sh" >/dev/null 2>&1; rc=$?
assert "bootstrap exits 0" test "$rc" -eq 0
[ "$(state_field '[.deps[]|select(.status=="installed" or .status=="up-to-date")]|length')" -ge 3 ] \
  && ok ">=3 deps installed" || bad "only $(state_field '[.deps[]|length]') deps present"
assert "no failed deps" test "$(state_field '[.deps[]|select(.status=="failed")]|length')" -eq 0
assert "state file is valid JSON" jq -e . "$STATE"

# --- Test 2: install over existing config (preservation) -------------------
echo "[2] install over existing configuration (must not be lost)"
reset_state
mkdir -p "$XDG_CONFIG_HOME/herdr"
USERCFG="$XDG_CONFIG_HOME/herdr/config.toml"
printf 'theme = "dark"\n[notifications]\nsound = true\n' > "$USERCFG"
before=$(sha256sum "$USERCFG" | cut -d' ' -f1)
bash "$ROOT/scripts/bootstrap.sh" >/dev/null 2>&1
after=$(sha256sum "$USERCFG" | cut -d' ' -f1)
[ "$before" = "$after" ] && ok "user config.toml byte-identical" || bad "user config.toml was modified"

# --- Test 3: idempotency ---------------------------------------------------
echo "[3] idempotency (re-run -> up-to-date, no reinstall)"
bash "$ROOT/scripts/bootstrap.sh" >/dev/null 2>&1
ni=$(state_field '[.deps[]|select(.status=="installed")]|length')
nu=$(state_field '[.deps[]|select(.status=="up-to-date")]|length')
{ [ "${ni:-0}" -eq 0 ] && [ "${nu:-0}" -ge 3 ]; } && ok "re-run: 0 fresh installs, >=3 up-to-date" \
  || bad "re-run: installed=$ni up-to-date=$nu (expected 0 / >=3)"

# --- Test 4: graceful degradation (missing prereq) -------------------------
echo "[4] graceful degradation (roamgate needs bun; bun absent)"
roam=$(state_field '.deps[]|select(.id=="roamgate")|.status')
[ "$roam" = "skipped" ] && ok "roamgate skipped (not failed) without bun" || bad "roamgate status=$roam (expected skipped)"
bash "$ROOT/scripts/bootstrap.sh" >/dev/null 2>&1; rc=$?
assert "bootstrap exits 0 with a degraded dep" test "$rc" -eq 0

# --- Test 5: doctor --json (machine-readable) ------------------------------
echo "[5] doctor --json (machine-readable)"
djson=$(bash "$ROOT/scripts/doctor.sh" --json 2>/dev/null)
assert "doctor --json is valid JSON" jq -e . <<<"$djson"
assert "doctor --json has herdr_version" jq -e '.herdr_version' <<<"$djson"
assert "doctor --json lists all locked deps (>=11)" jq -e '(.deps|length) >= 11' <<<"$djson"
assert "installed dep reported installed" jq -e '[.deps[]|select(.id=="structupath.swarm")][0].status=="installed"' <<<"$djson"

# --- Test 6: doctor human ---------------------------------------------------
echo "[6] doctor (human-readable)"
dhuman=$(bash "$ROOT/scripts/doctor.sh" 2>/dev/null)
printf '%s' "$dhuman" | grep -q "HerdR Powerpack — doctor" && ok "human header present" || bad "missing human header"
printf '%s' "$dhuman" | grep -q "Swarm (worktree fan-out)" && ok "dep names rendered" || bad "dep names missing"

# --- Test 7: doctor --strict (CI gate) ------------------------------------
echo "[7] doctor --json --strict (CI exit code)"
bash "$ROOT/scripts/doctor.sh" --json --strict >/dev/null 2>&1; s=$?
# roamgate is a default dep that degrades to 'skipped' (missing) here -> strict must fail
[ "$s" -ne 0 ] && ok "strict exits non-zero when a default dep is degraded" || bad "strict unexpectedly passed with a degraded default"

# --- Test 8: HOLD deps never auto-installed --------------------------------
echo "[8] HOLD deps are never auto-installed"
reset_state
bash "$ROOT/scripts/bootstrap.sh" >/dev/null 2>&1
planno=$(state_field '.deps[]|select(.id=="official.plannotator")|.status')
[ "$planno" = "held" ] && ok "plannotator status=held" || bad "plannotator status=$planno (expected held)"

# --- summary ----------------------------------------------------------------
echo
echo "=== summary: $PASS passed, $FAIL failed (HOME: $TESTHOME) ==="
[ "$FAIL" -gt 0 ] && echo "  failed:$FAILED_NAMES"
if [ "$KEEP" = "1" ]; then echo "  (kept test HOME for inspection)"; else rm -rf "$TESTHOME"; fi
[ "$FAIL" -eq 0 ]
