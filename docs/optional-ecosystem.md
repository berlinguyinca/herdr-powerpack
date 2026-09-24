# Optional & rejected ecosystem (Phase 6)

The Powerpack ships a small default bundle and keeps the rest of the ecosystem
**opt-in** or **out entirely**. Every candidate was evaluated against two rules:
1. **Does it fill a gap** the default bundle lacks?
2. **Does it respect the single-authoritative-state boundary** (no competing
   task/dispatch state machine)?

## OPTIONAL (disabled by default; enable per-host via the enable list)

| Plugin | What it adds | Prereq / note | Enable |
| --- | --- | --- | --- |
| `barnuri/herdr-notifications` | **Telegram** notifications | needs a **bot token (secret)** + outbound network | `enable.list` |
| `zenbu-labs/terminal-browser` | terminal browser | downloads via an install script (Electron) | `enable.list` |

> `quinnjr/herdr-notifications` (native OS desktop notifications) was briefly made
> optional during Phase 2, but that was an isolated-HOME test artifact (rustup's default
> toolchain lives under `~/.rustup`); with the real HOME it builds fine and is **default**
> again. It needs a working Rust toolchain and is a no-op on headless.

These are not defaults because they are either build/toolchain-heavy, need a
secret, or download extra runtimes — but they add real capability with no
state-machine conflict.

## HOLD (recorded, not installed)

| Plugin | Why held | Promotion path |
| --- | --- | --- |
| `plannotator/herdr-plannotator` | not currently functional (hard-coded `official.browser` dependency on a **deprecated** plugin) | promote to ADOPT when the upstream drops the deprecated dependency (meanwhile `persiyanov/herdr-reviewr` covers the diff-review capability) |

## REJECTED (never installed by the Powerpack)

| Plugin | Why rejected |
| --- | --- |
| `MatheusBBarni/herdr-tasks` | **no license** + competing task-state model (violates the single-authoritative-state boundary) |
| `husniadil/herdr-dispatch` | competing dispatch/state model; depends on unlicensed herdr-tasks |
| `tyler-jewell/herdr-plugins` (herdr-tasks-board) | low activity; no capability the default bundle lacks |

`herdr-tasks` / `herdr-dispatch` are the **hard boundary**: Pi Engineering is the
sole orchestrator, so the Powerpack never installs a second task/dispatch state
machine. `doctor` cross-references the live plugins against this rejected set and
warns if any is present (`competing_state_plugins` in `--json`).

## Decision record
- **Not added:** tasks, dispatch, tasks-board — competing state + licensing.
- **Optional:** desktop notifications, Telegram notifications, terminal browser —
  real capability, opt-in, no state conflict.
- **Held:** Plannotator — broken upstream dependency; re-evaluate on upstream fix.
- The default bundle remains: browser, mobile (roamgate), swarm, worktrees,
  file review, GitHub/CI (gh-checks, pr-board).
