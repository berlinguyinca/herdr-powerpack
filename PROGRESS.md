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

## Phase 1 — Thin meta-plugin  ⬜ TODO
- [ ] `herdr-plugin.toml` (current format)
- [ ] `config/bundle.lock.json` (pinned SHAs)
- [ ] `scripts/common.sh`, `bootstrap.sh`, `reconcile.sh`, `doctor.sh`
- [ ] ownership-aware idempotent config
- [ ] `README.md`, `LICENSE`, `.gitignore`
- [ ] tests: clean install, install-over-existing-config, idempotency

## Phase 2 — Core bundle  ⬜ TODO
- [ ] wire browser, roamgate, swarm, worktreeinclude, file-annotator, gh-checks, pr-board, notifications
- [ ] env-aware enablement + graceful degradation

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
