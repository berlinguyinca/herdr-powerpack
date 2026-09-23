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

## Phase 3 — Security / update / rollback  ⬜ TODO
- [ ] pinning + provenance, preflight, snapshot/accept, rollback, unsafe-listener checks, secret redaction

## Phase 4 — Pi Engineering integration  ⬜ TODO
- [ ] expose capabilities without duplicating orchestration/state

## Phase 5 — Ansible / multi-host  ⬜ TODO
- [ ] role: prereqs, ensure herdr, install pinned release, reconcile, doctor; Linux/macOS; headless degrade

## Phase 6 — Optional ecosystem  ⬜ TODO
- [ ] evaluate tasks/dispatch/telegram/terminal-browser; add only if gap + no competing state

## Acceptance tests (spec 08)
- [ ] 1 clean install  - [ ] 2 install-over-config  - [ ] 3 idempotency
- [ ] 4 browser launch/attach  - [ ] 5 local-site inspection  - [ ] 6 mobile private binding
- [ ] 7 plannotator smoke  - [ ] 8 worktree/swarm  - [ ] 9 github auth/no-auth
- [ ] 10 optional-failure isolation  - [ ] 11 incompatible-update block  - [ ] 12 rollback
- [ ] 13 uninstall preservation  - [ ] 14 doctor human + machine output
