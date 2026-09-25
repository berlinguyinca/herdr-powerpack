# HerdR Powerpack — Progress Log

Visible checklist. Updated at every milestone.

## Phase 0 — Research + brainstorming + audit  ✅ DONE
- [x] Located + unzipped `herdr-powerpack-specs.zip`; read all 12 files
- [x] Inspected CURRENT HerdR (0.9.1) plugin API, install/update, manifest format
- [x] Independently verified all 14 candidate upstream repos (existence/owner/license/activity)
- [x] Resolved the browser confusion (ogulcancelik deprecated → terminal-browser; StructuPath for QA)
- [x] Discovered Plannotator's broken `official.browser` dependency → HOLD
- [x] Discovered Roamgate is the correct private-by-default mobile surface (vs eyalev/herdr-web)
- [x] Corrected stale name `barnuri/herdr-telegram-notifications` → `barnuri/herdr-notifications`
- [x] Captured pinned HEAD commit SHAs for the lock
- [x] `docs/upstream-audit.md` (ADOPT/OPTIONAL/ADAPT/HOLD/REJECT + corrections)
- [x] `docs/architecture.md` (design decisions)

## Phase 1 — Thin meta-plugin  ✅ DONE (tests pass)
- [x] `herdr-plugin.toml` (current format; validates via `herdr plugin link`)
- [x] `config/bundle.lock.json` (pinned full commit SHAs, licenses, install hooks, security notes)
- [x] `scripts/common.sh`, `bootstrap.sh`, `reconcile.sh`, `doctor.sh`, `versions.sh`, `board.sh`, `update.sh`, `rollback.sh`
- [x] fault-tolerant bootstrap (best-effort, always exit 0); `pp_herdr_cli` runs registry ops socket-less
- [x] ownership-aware idempotent config (user config.toml untouched; verified byte-identical)
- [x] doctor human + `--json` + `--strict`; unsafe-listener check; secret redaction
- [x] `README.md`, `LICENSE` (MIT), `.gitignore`, `docs/security.md`, `docs/troubleshooting.md`
- [x] `tests/run-tests.sh`: 16/16 pass (clean install, config preservation, idempotency,
      graceful degradation, doctor json/human/strict, HOLD isolation)
- [x] end-to-end: manifest link + `plugin action invoke` executes through a Herdr server

## Phase 2 — Core bundle  ✅ DONE (tests pass)
- [x] all ADOPT deps wired in `bundle.lock.json` (full commit SHAs); full default bundle installs with **0 failures**
- [x] verified installs: browser, swarm, worktreeinclude (bash); file-annotator, gh-checks (checksum-verified prebuilt); pr-board (go build)
- [x] env-aware enablement + graceful degradation: roamgate→skipped without bun; gh deps degrade when unauthenticated; optional deps not-selected
- [x] **mobile private binding:** discovered roamgate's `service install` actually defaults to `HOST=0.0.0.0` (not loopback); Powerpack now OWNS `roamgate.env` and enforces `HOST=127.0.0.1` (loopback) by default (`POWERPACK_MOBILE_BIND=loopback|tailscale|lan`); verified end-to-end (binary binds 127.0.0.1:8787, HTTP 200)
- [x] doctor reports `roamgate_bind`; `--strict` fails on a public bind
- [x] **notifications demoted default→optional** (must compile; Herdr's sandboxed build env may not resolve a rustup default toolchain)
- [x] `tests/run-tests.sh`: **20/20 pass** (added roamgate private-bind test)
- [x] real host restored clean after roamgate live-test (no service, no token, no 0.0.0.0 exposure)

## Phase 3 — Security / update / rollback  ✅ DONE (tests pass)
- [x] pinning + provenance (lock: full SHAs, licenses, install hooks, security notes, verified dates)
- [x] **update lifecycle**: snapshot → preflight (pinned-ref change report) → force re-pin → smoke gate → accept/rollback
- [x] **smoke gate**: detects a default dep regressing installed→failed/missing and **auto-rolls-back**, exit 1
- [x] **rollback**: restores each dep at its **snapshotted** ref (works even if the lock changed); restores lost deps
- [x] unsafe-listener check (doctor) + secret redaction (common.sh)
- [x] bugs found & fixed: lock top-level key is `dependencies` (not `deps`); state stores `default` as string `"true"` (smoke gate now compares the string)
- [x] `tests/run-tests.sh`: **26/26 pass** (added update snapshot/accept, rollback restore, auto-rollback-on-regression)

## Phase 4 — Pi Engineering integration  ✅ DONE
- [x] `docs/integration-boundaries.md`: capability-provider, not orchestrator; Pi Engineering is the sole authoritative state owner
- [x] Powerpack installs NO task/dispatch plugin; lock `rejected` set records the competing-state plugins (herdr-tasks, herdr-dispatch, herdr-tasks-board) + reasons
- [x] **doctor guard**: `integration_check` cross-references live plugins (by `source.owner/repo`) against the lock's `rejected` set; flags any present competing-state plugin (`competing_state_plugins` in `--json`); human output shows the boundary status
- [x] `tests/run-tests.sh`: **29/29 pass** (added integration-boundary detection test)
- [x] bug fixed: `pipefail` + `grep` no-match made a `|| printf '[]'` fallback double-emit `[]` in the doctor JSON (removed the redundant fallback)

## Phase 5 — Ansible / multi-host  ✅ DONE
- [x] `ansible/roles/herdr-powerpack/`: prereqs (per OS family), install herdr+pinned powerpack, reconcile, doctor
- [x] host-agnostic (uses `ansible_os_family`/`ansible_architecture`; no hard-coded host names) — works on fry/beast/bender/macbook-m4
- [x] Linux + macOS package handling; headless nodes degrade gracefully (doctor reports GUI caps degraded, not failed)
- [x] private mobile bind enforced via `powerpack_mobile_bind` (loopback default; tailscale/lan options)
- [x] optional toolchains (bun→roamgate, go→pr-board) off by default; strict-doctor gate optional
- [x] `ansible/playbook.yml`, `group_vars/all.yml`, `README.md`
- [x] `tests/run-tests.sh`: **32/32 pass** (added ansible YAML parse + host-agnostic + role structure tests)

## Phase 6 — Optional ecosystem  ✅ DONE
- [x] `docs/optional-ecosystem.md`: OPTIONAL (notifications/telegram/terminal-browser) vs HOLD (plannotator) vs REJECTED (tasks/dispatch/tasks-board) + rationale
- [x] rule: fill a gap + no competing state machine; task/dispatch remain the hard boundary
- [x] lock reflects decisions (optional deps default:false; competing-state rejected)

## Post-implementation fix — notifications (user: "notifications are fun")
- [x] root cause: rustup's default toolchain lives under `~/.rustup`; an isolated-HOME test made cargo think no default was configured (production with real HOME builds fine)
- [x] notifications **re-enabled as default**; Powerpack sets `RUSTUP_HOME`/`RUSTUP_TOOLCHAIN` for cargo deps (`pp_ensure_rustup_env`)
- [x] verified: full default bundle now installs notifications (7 installed, 0 failed); harness **34/34 pass** (added Test 15: notifications install + binary builds on a Rust host)

## CI + herdr install (user supplied the official install method)
- [x] herdr official install: `curl -fsSL https://herdr.dev/install.sh | sh` (checksum-verified, os/arch-detecting, installs to ~/.local/bin)
- [x] **CI workflow** `.github/workflows/ci.yml`: pins herdr v0.9.1 (release asset + sha256 verified by hand here), installs Rust (notifications build), optional pyyaml + shellcheck; runs the isolated-HOME harness; archives debug on failure
- [x] Ansible role: `powerpack_install_herdr` now uses the official installer by default; `powerpack_herdr_url` remains a pin override for reproducible deploys
- [x] verified the CI pin's sha256 matches the downloaded release binary exactly; harness still **35/35 pass**

## Post-implementation fix — review capability replacement (user: implement replacement recommendations)
- [x] **`persiyanov/herdr-reviewr`** (MIT, active, v0.39.0, min_herdr 0.7.5) adopted as the **default review capability**, replacing the held (broken) Plannotator
- [x] verified: installs cleanly on HerdR 0.9.1; **checksum-verified prebuilt binary** (no Rust build, no runtime network); diff review + line comments back to the agent; auto-opens on worktree.created/opened (composes with swarm)
- [x] full default bundle now installs **8 deps, 0 failed** (browser, mobile-degrades, swarm, worktree, file-annotator, gh-checks, pr-board, notifications, reviewr); harness **34/34 pass**
- [x] docs updated: audit (reviewr ADOPT, Plannotator HOLD w/ replacement), integration-boundaries, optional-ecosystem, README, spec-compliance

## Line-by-line spec comparison
- [x] `docs/spec-compliance.md`: maps every spec requirement -> implementation -> status
- [x] intentionally deferred (with reasons): live browser launch/attach (no display), live swarm fan-out (needs a project), Plannotator smoke (HOLD — broken upstream), live Ansible run (needs fleet)

## Acceptance tests (spec 08)
- [x] 1 clean install  - [x] 2 install-over-config  - [x] 3 idempotency
- [ ] 4 browser launch/attach  - [ ] 5 local-site inspection  - [x] 6 mobile private binding
- [ ] 7 plannotator smoke  - [ ] 8 worktree/swarm  - [x] 9 github auth/no-auth
- [x] 10 optional-failure isolation  - [x] 11 incompatible-update block  - [x] 12 rollback
- [x] 13 uninstall preservation  - [x] 14 doctor human + machine output
- [ ] (deferred 4/5/7/8: no display/project in this env, or HOLD upstream — see spec-compliance.md)
