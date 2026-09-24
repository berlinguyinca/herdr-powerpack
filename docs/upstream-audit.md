# HerdR Powerpack — Upstream Audit (Phase 0)

> Status: **VERIFIED** — every claim below was checked live on 2026-09-21 against the
> installed `herdr 0.9.1`, the `herdrdev/herdr@v0.9.1` docs, and the GitHub API.
> Repository names, capabilities, versions, and existence were **not** trusted from the
> spec. This document is the source of truth for which upstreams the Powerpack adopts.

---

## 1. Ground truth: the HerdR plugin model (v0.9.1)

Canonical source: `herdrdev/herdr@v0.9.1`, `docs/plugins.mdx` + `docs/marketplace.mdx`.
Installed binary: `herdr 0.9.1` at `~/.local/bin/herdr`. Config: `~/.config/herdr/config.toml`.

- A plugin is a directory with a **`herdr-plugin.toml`** manifest + argv commands.
  There is no SDK or sandbox: the **entire `herdr` CLI is the plugin API**.
- Required manifest fields: `id`, `name`, `version`, `min_herdr_version`. Optional:
  `description`, `platforms = ["linux","macos","windows"]`.
- Manifest entrypoints:
  - `[[build]]` — argv, run **during `herdr plugin install`** after the preview, **before
    registration**, with **no server and no runtime env**. Can run any command, including
    `herdr plugin install …`. A build failure **aborts the install**.
  - `[[startup]]` — one-shot init, run once per enabled plugin after the server is up;
    receives `HERDR_PLUGIN_EVENT=startup`.
  - `[[actions]]` — `id/title/contexts/command`; invoked via
    `herdr plugin action invoke <plugin.id>.<action>`.
  - `[[events]]` — `on="<event>"` hooks (e.g. `worktree.created`,
    `pane.agent_status_changed`).
  - `[[panes]]` — `id/title/placement(command)`, placement ∈ overlay/popup/split/tab/zoomed.
  - `[[link_handlers]]` — route modified-clicks on matching URLs to an action.
- Install: `herdr plugin install OWNER/REPO[/SUBDIR] --ref <REF> -y`.
  - `--ref` pins a revision (our **locking mechanism**).
  - `-y` noninteractive.
  - Reinstall replaces the managed checkout. There is **no `plugin update`** in v1 —
    reinstall to refresh.
  - `herdr plugin uninstall <id-or-source>`, `enable`, `disable`, `list`,
    `config-dir <id>`, `action list/invoke`, `log list`, `pane open`.
- Injected env at runtime: `HERDR_BIN_PATH`, `HERDR_SOCKET_PATH`, `HERDR_ENV=1`,
  `HERDR_PLUGIN_ID`, `HERDR_PLUGIN_ROOT` (managed checkout — **do not store durable
  state**), `HERDR_PLUGIN_CONFIG_DIR` (user-editable config; seeded from legacy config),
  `HERDR_PLUGIN_STATE_DIR` (local runtime state), `HERDR_PLUGIN_CONTEXT_JSON`,
  workspace/tab/pane ids.
- Plugins are **global to the user** and available in every session; install/link work
  with **no server running**.
- Marketplace = public GitHub repos tagged `herdr-plugin` with parseable manifests.
  **Unreviewed** — treat every plugin as third-party code execution.

### Consequences for the Powerpack design
1. The Powerpack **is** one HerdR plugin; its `[[build]]` hook (plain Bash) is the
   bootstrap that installs upstreams at pinned `--ref`.
2. Because a build failure aborts install, the bootstrap **must be fault-tolerant**
   (best-effort, always exit 0 for non-critical per-dependency failures) — this is how
   "optional plugin failure must not make HerdR unusable" and "headless must degrade
   gracefully" are satisfied.
3. The Powerpack needs only **bash + git + curl (+ jq)** to install *itself*. bun/go/
   cargo/node are **per-dependency** prerequisites that decide what gets enabled.

---

## 2. Browser / in-terminal inspection

The spec listed `StructuPath/herdr-browser`. Verification reveals **three** real options:

| Repo | Stars | Status | id | min_herdr | Notes |
| --- | --- | --- | --- | --- | --- |
| `ogulcancelik/herdr-browser` | 352 | **DEPRECATED** | — (no manifest) | — | First-party, now "no longer maintained. Use terminal-browser instead." |
| `zenbu-labs/terminal-browser` | 3185 | active (2026-09-20) | `zenbu-labs.terminal-browser` | 0.8.2 | Electron offscreen "real browser"; herdr-plugin is a thin `open-split`. Build = `curl …\|bash`. |
| `StructuPath/herdr-browser` | 18 | active (2026-09-16) | `structupath.browser` | 0.7.0 | CDP-based; **QA scenarios + commit-bound screenshots**, console/network error visibility, observe-only/takeover, localhost routing, recording. Drives `agent-browser` + Chromium; zero-setup launch needs no agent-browser. |

**Decision:**
- **ADOPT `StructuPath/herdr-browser`** (primary browser). It is the only verified plugin
  that satisfies the spec's enumerated capabilities: real Chromium, local/generated-site
  inspection, CDP/Playwright automation, human observation/takeover, console/network/
  error visibility, screenshots + QA evidence, safe localhost handling. Its security
  posture is sound: attaches to an existing CDP or launches a **local** Chromium (no
  public CDP port by default), `chmod 700` state dir, sanitized workspace ids.
- **OPTIONAL `zenbu-labs/terminal-browser`** — the far more popular "real browser in the
  terminal" experience; enabled on request for hosts wanting the full Electron browser.
- **CORRECTION (stale assumption):** the natural "first-party browser" (`ogulcancelik/
  herdr-browser`) is **deprecated**. It is NOT adopted.

Prereqs: Node ≥ 20 (present). `agent-browser` (vercel-labs) is optional — required only
for shared sessions / recording / saved QA scenarios; the Powerpack installs it when the
browser's QA capability is enabled.

## 3. Plannotator bridge

| Repo | Stars | id | min_herdr | Decision |
| --- | --- | --- | --- | --- |
| `plannotator/herdr-plannotator` | 26 | `official.plannotator` | 0.7.5 | **HOLD** |

**Why HOLD (verified, not speculative):** `src/constants.ts` hard-codes
`BROWSER_PLUGIN_ID = "official.browser"` and opens it via
`herdr plugin pane open --plugin official.browser --entrypoint browser --env
HERDR_BROWSER_INITIAL_URL=…`. The README still says to install
`ogulcancelik/herdr-browser`, which is **deprecated and no longer ships a manifest**.
No currently-maintained browser registers the plugin id `official.browser` (verified:
terminal-browser = `zenbu-labs.terminal-browser`; StructuPath = `structupath.browser`).
Therefore the integration **does not function out-of-the-box**.

Per the integration-boundary rule ("use the existing verified Plannotator integration;
Plannotator owns its semantics") and "do not create a replacement just because a
candidate fails," we do **not** fork it. It is **HOLD**: not in the default bundle,
recorded in the lock as `enabled:false`, and promotable to ADOPT the moment upstream
repoints `official.browser` to a maintained browser (or exposes the id as configurable).
Plannotator's own plan/review semantics are untouched.

## 4. Mobile / web surface

| Repo | Stars | Decision |
| --- | --- | --- |
| `powerfooI/roamgate` | 230 | **ADOPT** |
| `eyalev/herdr-web` | 5 | **REJECT** (superseded) |
| `barnuri/herdr-web` | 12 | OPTIONAL (noted; not selected) |

**ADOPT `powerfooI/roamgate`** (v0.7.8, id `roamgate`, min_herdr 0.7.2, platforms
linux/macos/windows): a full browser **client** — workspaces, tabs, panes, agent status,
session inspection, file explorer, diff annotations; PWA install on iPhone/iPad/macOS/
Chrome; "private remote access" workflow. Its security model is exactly the spec's
private-by-default model (**`SECURITY.md`**): loopback binds bypass login; non-loopback
requires a strong `ROAMGATE_PASSWORD` + VPN/HTTPS; "A VPN, SSH tunnel, or reverse proxy
forwarding to loopback becomes the entire remote access boundary" — the **Tailscale-oriented**
model the spec asks for. It downloads a **checksum-verified** prebuilt release binary.

- **Phase 2 finding (corrects the documented default):** `SECURITY.md` *describes* a
  loopback-oriented model, but roamgate's **`service install` actually writes
  `HOST=0.0.0.0`** (verified: the running process bound `0.0.0.0:8787` and advertised many
  LAN IPs). **Therefore the Powerpack OWNS `roamgate.env` and enforces `HOST=127.0.0.1`
  (loopback) by default** (`POWERPACK_MOBILE_BIND=loopback|tailscale|lan`). `doctor`
  reports the bind and `--strict` fails on any public bind. Verified end-to-end: with the
  Powerpack's env the prebuilt binary binds `127.0.0.1:8787` and serves HTTP 200.

**REJECT `eyalev/herdr-web`** (v0.1.0, 5★): loopback-only (port 7930), minimal, strictly
superseded by Roamgate in maturity and feature set. (Correction: the spec's mobile
candidate was the wrong project.)

Prereq: **`bun`** (absent on the current host → the Powerpack installs it as an OS
prerequisite when enabling the mobile capability).

## 5. Swarm / worktrees (reuse HerdR worktree primitives)

| Repo | Stars | id | min_herdr | Decision |
| --- | --- | --- | --- | --- |
| `StructuPath/herdr-swarm` | 8 | `structupath.swarm` | 0.7.4 | **ADOPT** |
| `serhii-chernenko/herdr-worktreeinclude` | 2 | `serhii-chernenko.worktreeinclude` | 0.7.4 | **ADOPT** |

- `herdr-swarm`: worktree-per-agent fan-out, per-slot change visibility, review-first
  harvest. Pure **bash + git** (no build). Low risk. Reuses HerdR worktree/tab primitives.
- `herdr-worktreeinclude`: project-local git worktrees + `.worktreeinclude` restore, via
  `worktree.created` / `worktree.removed` **event hooks**. Pure **bash + git**. Low risk.

## 6. Human file review

| Repo | Stars | id | min_herdr | Decision |
| --- | --- | --- | --- | --- |
| `JonasBaeumer/herdr-file-annotator` | 61 | `jonasbaeumer.file-annotator` | **0.8.0** | **ADOPT** |

Agent-summoned, **blocking** diff review via an MCP tool (`review_changes`): a review
pane opens beside the agent and it waits for the verdict + line annotations. Build =
`fetch-or-build.sh`: downloads the **release tarball for the declared version and
verifies SHA-256**, falling back to `cargo build --release` (cargo present here).
Popular and actively maintained (pushed 2026-09-21). Requires HerdR ≥ 0.8.0 (host is 0.9.1).

## 7. GitHub / CI

| Repo | Stars | id | min_herdr | Decision |
| --- | --- | --- | --- | --- |
| `itisbryan/herdr-gh-checks` | 3 | `herdr-gh-checks` | 0.7.0 | **ADOPT** |
| `cdowell09/herdr-pr-board` | 4 | `cdowell09.pr-board` | **0.8.0** | **ADOPT** |

- `herdr-gh-checks` (Go + Charm): watches the current PR's CI in a pane, CI/merge status
  on sidebar rows, a merge popup. Build = fetch-or-build (prebuilt Go binary, SHA-256
  verified; fallback `go build` — Go present). `[[startup]]` runs `--sidebar`.
- `herdr-pr-board` (Go): cross-repository PR dashboard with CI status + configurable
  agent reviews. Build = `go build` (Go present). min_herdr 0.8.0.

Both require **GitHub auth** (`gh`) to be useful. **Decision on auth:** install them by
default, but the doctor reports **degraded** (not failed) when unauthenticated, so the
bundle stays usable — satisfying "GitHub integration handles authenticated/
unauthenticated states."

## 8. Notifications

| Repo | Stars | id | min_herdr | Decision |
| --- | --- | --- | --- | --- |
| `quinnjr/herdr-notifications` | 1 | `quinnjr.herdr-notifications` | 0.7.0 | **ADOPT** (desktop) |
| `barnuri/herdr-notifications` | 1 | (JS) | — | **OPTIONAL** (Telegram) |

- **ADOPT `quinnjr/herdr-notifications`** (default): native **OS desktop** notifications on
  `pane.agent_status_changed` (blocked/done only, deduped). No network, no secrets.
  Build = `cargo build --release`; no prebuilt binary, so it needs a working Rust toolchain.
  **Phase 2+ correction:** the earlier "can't build under HerdR" finding was an **isolated-HOME
  test artifact** — rustup's default toolchain lives under `~/.rustup`, so a redirected HOME
  made cargo think no default was configured. With the real HOME it builds fine (verified).
  The Powerpack sets `RUSTUP_HOME`/`RUSTUP_TOOLCHAIN` for cargo deps so it builds robustly;
  it degrades (skips) on hosts without a working Rust toolchain, and is a no-op on headless.
- **OPTIONAL `barnuri/herdr-notifications`**: **Telegram** notifications on idle/blocked/
  done. Needs a **bot token (secret)** + outbound network → **disabled by default**,
  user-configured, never written to logs/UI.
  - **CORRECTION (stale name):** the spec listed `barnuri/herdr-telegram-notifications`;
    that repo **does not exist**. The canonical repo is `barnuri/herdr-notifications`.

## 9. Task / dispatch / other (HOLD or REJECT)

| Repo | Stars | License | Decision |
| --- | --- | --- | --- |
| `MatheusBBarni/herdr-tasks` | 1 | **none** | **REJECT** (default) |
| `husniadil/herdr-dispatch` | 1 | MIT | **HOLD** (evaluation) |
| `tyler-jewell/herdr-plugins` | 0 | MIT | **HOLD** (evaluation) |

- `herdr-tasks`: Kanban task runner (OpenTUI + `htasks` CLI). **No license** (legal
  blocker for default inclusion) and a **competing task-state model**. REJECT from the
  default bundle.
- `herdr-dispatch`: "worker agent pane per ready task … stop at review" — depends on
  `herdr-tasks` and introduces a **competing dispatch/state model**. Per the boundary
  rule ("one authoritative state model": AutoSpec → GitHub Issues → Pi Engineering
  Mission → workers → review → completion), it must **not** be enabled until reconciled.
  **HOLD**.
- `tyler-jewell/herdr-plugins`: 0★, low activity, monorepo, no capability we currently
  lack. **HOLD**.

---

## 10. Corrections to the spec's stale assumptions (summary)

1. **Browser:** the spec's `StructuPath/herdr-browser` is adopted, but the "obvious"
   first-party `ogulcancelik/herdr-browser` is **deprecated**; the popular successor is
   `zenbu-labs/terminal-browser` (3185★). None of these is a stale dead-end, but the
   deprecation must not be missed.
2. **Plannotator:** `plannotator/herdr-plannotator` is **not currently functional**
   (hard-coded `official.browser` dependency on a deprecated plugin) → **HOLD**, not
   ADOPT, with a documented promotion path.
3. **Mobile:** the spec's `eyalev/herdr-web` is **superseded**; the correct choice is
   `powerfooI/roamgate` (230★, private-by-default).
4. **Telegram:** the spec's `barnuri/herdr-telegram-notifications` **does not exist**;
   canonical repo is `barnuri/herdr-notifications`.
5. **Toolchain:** `bun` is a real prerequisite for roamgate/plannotator and is **absent**
   on the current host → the Powerpack must install it as an OS prerequisite when
   enabling those capabilities.

## 11. Default bundle (lock) summary

ADOPT (enabled by default when prereqs are met):
- `structupath.browser` (StructuPath/herdr-browser)
- `roamgate` (powerfooI/roamgate) — needs bun
- `structupath.swarm` (StructuPath/herdr-swarm)
- `serhii-chernenko.worktreeinclude`
- `jonasbaeumer.file-annotator`
- `herdr-gh-checks`, `cdowell09.pr-board` — degrade when unauthenticated
- `quinnjr.herdr-notifications` (desktop; needs a working Rust toolchain)

OPTIONAL (disabled by default):
- `zenbu-labs.terminal-browser`
- `barnuri/herdr-notifications` (Telegram; needs token)

HOLD (recorded, not installed):
- `official.plannotator` (broken browser dependency)
- `husniadil/herdr-dispatch`, `tyler-jewell/herdr-plugins` (evaluated later)

REJECT (not included):
- `eyalev/herdr-web` (superseded)
- `MatheusBBarni/herdr-tasks` (no license + competing state model)
