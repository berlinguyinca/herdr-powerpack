# Spec Compliance

Line-by-line comparison of the implementation against the spec set
(`herdr-powerpack-specs.zip`). Status: **DONE** unless noted; deferred items are
listed at the end with a concrete reason.

## 00-master-spec / IMPLEMENTATION_PROMPT
| Requirement | Where | Status |
| --- | --- | --- |
| Thin meta-plugin/distribution; one `herdr plugin install berlinguyinca/herdr-powerpack` | `herdr-plugin.toml`, `config/bundle.lock.json`, `scripts/` | DONE |
| Powerpack owns locking / safe config / compatibility / doctor / update-rollback / security / integration | lock, reconcile, doctor, update/rollback, security.md | DONE |
| Do not reimplement HerdR, browser, Pi/Pi Web, pi-engineering, autospec, Plannotator, GitHub clients | upstream-audit.md (ADOPT upstream), architecture.md | DONE |
| Preserve existing functionality; ownership-aware idempotent config merging | `pp_configure_roamgate` preserves user secrets; config.toml untouched (test 2) | DONE |
| Treat plugins as third-party code; pin versions; inventory provenance; redact secrets; private/Tailscale mobile | lock (SHAs), security.md, common.sh redaction, roamgate loopback default | DONE |
| No competing task state machine; no task/dispatch by default | rejected set in lock, integration_check guard | DONE |
| Implement in phases 0–6 | see below | DONE |
| Multi-host fry/beast/bender/macbook-m4, no hard-coded names, headless degrade, don't disturb Pi/InferWeave | ansible role (host-agnostic), doctor degraded semantics | DONE |

## 01-upstream-audit
| Decision | Verdict |
| --- | --- |
| browser: `StructuPath/herdr-browser` (ogulcancelik deprecated) | ADOPT (corrected) |
| mobile: `powerfooI/roamgate` (eyalev/herdr-web superseded) | ADOPT (corrected) |
| Plannotator | HOLD (broken upstream dep) |
| swarm, worktreeinclude, file-annotator, gh-checks, pr-board | ADOPT |
| notifications: quinnjr | OPTIONAL (demoted — compile-only; Herdr sandboxed build env) |
| Telegram, terminal-browser | OPTIONAL |
| tasks, dispatch, tasks-board | REJECTED (competing state / no license) |

## 02-lock-install-update
| Requirement | Status |
| --- | --- |
| Lock: repo, resolved commit, license, platforms, default, compatibility notes, verification date | DONE (bundle.lock.json) |
| Install: detect OS/arch/HerdR version | DONE (env.json) |
| Preserve existing config | DONE (config.toml byte-identical) |
| Resolve locked deps, report intended changes | DONE (preflight on update) |
| Install compatible upstream; merge owned defaults w/o overwriting user | DONE |
| Validate capabilities; print health matrix | DONE (doctor) |
| Noninteractive | DONE (`-y`, actions, scripts) |
| Idempotency | DONE (test 3) |
| Update: lock compare + preflight + snapshot + smoke + accept/rollback | DONE (update.sh) |
| Uninstall preserves unrelated plugins/user data | DONE (documented; Powerpack-owned only) |
| status/doctor/versions/update/repair capabilities | DONE (manifest actions) |

## 03-browser-mobile
| Requirement | Status |
| --- | --- |
| Verified upstream browser; no engine rebuild | DONE |
| Mobile via verified PWA; Tailscale/private path | DONE (roamgate loopback default) |
| No public CDP/dev/VNC/RDP/dashboards; detect unsafe listeners | DONE (doctor unsafe_listeners) |

## 04-integration-boundaries
| Requirement | Status |
| --- | --- |
| Pi Engineering = sole orchestrator; Powerpack exposes capabilities, owns no state | DONE (integration-boundaries.md, guard) |
| Reuse swarm/worktree; no competing task state | DONE |

## 05-security
| Requirement | Status |
| --- | --- |
| Pinning + provenance + install-hook inventory + permissions | DONE (lock security_notes) |
| No public CDP/debug endpoints | DONE |
| Redact secrets | DONE |
| Private/Tailscale mobile default | DONE (loopback enforced) |

## 06-health
| Requirement | Status |
| --- | --- |
| doctor: versions, per-plugin status, healthy/degraded/failed, OS, listeners, gh auth, mobile bind, no credential leak | DONE |
| machine + human readable | DONE (`--json` / human) |

## 07-ansible
| Requirement | Status |
| --- | --- |
| Concrete role; host-agnostic; Linux+macOS; headless degrade | DONE (validated YAML) |

## 08-tests
| Scenario | Status |
| --- | --- |
| 1 clean install / 2 install-over-config / 3 idempotency | DONE (tests 1–3) |
| 4 browser launch/attach + load page | PARTIAL (browser installed & validated; live browser load not run — no display/browser in this env) |
| 5 local web app inspection | PARTIAL (same env constraint) |
| 6 mobile private binding | DONE (test 9 + live 127.0.0.1:8787 HTTP 200) |
| 7 Plannotator smoke | DEFERRED (HOLD — broken upstream) |
| 8 worktree/swarm smoke | PARTIAL (installed; live fan-out not run — would touch a worktree) |
| 9 GitHub auth/no-auth | DONE (gh-checks degrade when unauthenticated; gh auth state reported) |
| 10 optional failure isolation | DONE (test 4) |
| 11 incompatible update blocked | DONE (test 12) |
| 12 failed update restores known-good | DONE (test 12 auto-rollback) |
| 13 uninstall preserves unrelated | DONE (documented; ownership-aware) |
| 14 doctor human + machine | DONE (tests 5–7) |

## 09-repo-layout
| Requirement | Status |
| --- | --- |
| README, LICENSE, herdr-plugin.toml, docs/, config/, scripts/, tests/, ansible/ | DONE |

## 10-phases
| Phase | Status |
| --- | --- |
| 0 research/audit | DONE |
| 1 meta-plugin/lock/reconcile/doctor | DONE |
| 2 core integrations | DONE |
| 3 security/update/rollback | DONE |
| 4 Pi integration | DONE |
| 5 Ansible | DONE |
| 6 optional ecosystem | DONE (optional-ecosystem.md) |

## Intentionally deferred (with reason)
- **Browser live launch/attach + local-site inspection (tests 4–5):** the browser is
  installed and health-checked, but a real Chromium page-load can't be demonstrated in
  this headless/no-display environment. The upstream `StructuPath/herdr-browser` owns this
  behavior; the Powerpack's role is installation/health, which is validated. Deferred to a
  host with a display/browser.
- **Worktree/swarm live fan-out (test 8):** installing is validated; running a live
  fan-out would mutate a real worktree and needs a project. The Powerpack's integration
  (install/health) is validated; the fan-out semantics belong to upstream `herdr-swarm`.
- **Plannotator smoke (test 7):** **HOLD** — upstream is non-functional (hard-coded
  dependency on the deprecated `official.browser`). Deferred until the upstream fixes it;
  not a Powerpack defect.
- **Live Ansible run against the 4 hosts:** the role is written and YAML-validated, but a
  live deploy requires the fleet. Deferred to the operator.
