# Integration Boundaries

The Powerpack is a **capability provider**, not an orchestrator. It owns the
*availability and health* of a set of plugins; it does **not** own any task,
dispatch, mission, or review **state machine**. Orchestration and policy stay
with the systems that already own them.

## Who owns what

| Concern | Owner | Powerpack role |
| --- | --- | --- |
| Orchestration, policy, missions, work items | **Pi Engineering** (`berlinguyinca/pi-engineering`) | none — exposes capabilities Pi Engineering can consume |
| Spec / issue workflow | **AutoSpec** (`berlinguyinca/autospec`) | none |
| Review semantics | **Plannotator** | the Plannotator bridge is **HOLD** (broken); the **diff-review** capability is provided by `persiyanov/herdr-reviewr` (default) |
| Browser / QA surface | upstream `StructuPath/herdr-browser` | installs + health-checks it; no re-implementation |
| Diff review / file viewer | upstream `persiyanov/herdr-reviewr` | installs it; comment-on-diff → agent |
| Mobile / remote surface | upstream `powerfooI/roamgate` | installs it **and owns its bind config** (loopback by default) |
| Worktree fan-out / harvest | upstream `StructuPath/herdr-swarm` | installs it |
| GitHub / CI visibility | upstream `herdr-gh-checks`, `herdr-pr-board` | installs them |

## The hard boundary: no competing task/dispatch state

Pi Engineering is the **single authoritative source of orchestration state**.
Any plugin that introduces its own task/dispatch state machine would create a
second, conflicting source of truth. The Powerpack therefore:

- **Does not install** task/dispatch plugins by default. The lock's `rejected`
  set records them and why:
  - `MatheusBBarni/herdr-tasks` — no license + competing task-state model.
  - `husniadil/herdr-dispatch` — competing dispatch/state model; depends on the
    unlicensed herdr-tasks.
  - `tyler-jewell/herdr-plugins` (herdr-tasks-board) — low activity, no unique
    capability the bundle already provides.
- **Guards the boundary at runtime:** `doctor` cross-references the live plugins
  against the lock's `rejected` set (by `owner/repo`) and reports any
  **competing-state** plugin that is present as a warning
  (`competing_state_plugins` in `--json`). This is defense-in-depth: if an
  operator manually adds such a plugin, the doctor surfaces the conflict.

## How capabilities are exposed (consumed, not owned)

The Powerpack makes capabilities *available and healthy*; the consuming system
*decides when and how to use them*:

- **Browser (QA/observe):** Pi Engineering or a QA step can launch/attach a
  browser to inspect a local site, read console/network errors, and capture
  screenshots. The Powerpack does not schedule this — it just ensures the
  capability works.
- **Mobile/remote (roamgate):** an operator reaches their Herdr instance over
  the tailnet to a **loopback** Roamgate. The Powerpack enforces the private
  bind; it does not run the remote session.
- **Swarm / worktrees:** parallel fan-out is a *capability*; whether and how to
  fan out is Pi Engineering's decision. The Powerpack does not add a second
  scheduler.

## What the Powerpack deliberately does NOT do

- No task queue, dispatch loop, or mission state.
- No re-implementation of Pi / Pi Web / pi-engineering / autospec / Plannotator.
- No competing GitHub client (it uses the existing `gh` auth state; `gh-checks`
  and `pr-board` read CI/PRs via `gh`).
- No changes to existing Pi/InferWeave configuration.
