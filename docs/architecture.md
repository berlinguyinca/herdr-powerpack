# HerdR Powerpack — Architecture

## What it is
`berlinguyinca/herdr-powerpack` is a **thin HerdR meta-plugin / distribution**. One
install:

```
herdr plugin install berlinguyinca/herdr-powerpack
```

provides a curated, tested HerdR capability bundle by **adopting existing upstream
plugins** (never re-implementing them). The Powerpack owns: dependency/version locking,
ownership-aware safe configuration, environment-aware bootstrap/reconcile, health/doctor
UX, update/rollback, security checks, and integration glue.

## Non-negotiable boundaries (from the spec, kept)
- Does **not** reimplement HerdR, browser engines, Pi/Pi Web, `pi-engineering`,
  `autospec`, Plannotator, GitHub clients, or any maintained compatible plugin.
- **One authoritative state model**: AutoSpec → GitHub Issues → Pi Engineering Mission →
  workers → review → completion. No competing task/dispatch state machine is enabled.
- **Preserve existing config/functionality.** Merging is ownership-aware and idempotent.
- **Private-by-default** mobile: Tailscale/loopback oriented; never auto-expose CDP, dev
  ports, VNC, or unauthenticated dashboards; report unsafe public listeners.

## Design decisions (brainstorming conclusions)

### D1 — The Powerpack needs no toolchain to install itself
The HerdR `[[build]]` hook runs at install time, as the user, with **no server**. It is
plain **Bash** (hard deps: `bash`, `git`, `curl`; `jq` for machine output). It installs
upstreams via `herdr plugin install <repo> --ref <pinned> -y`. bun/go/cargo/node are
**per-dependency** prerequisites that decide *what gets enabled*, never whether the
Powerpack itself installs. This makes the Powerpack installable on a bare Linux/macOS box
and lets headless systems degrade gracefully.

### D2 — Fault-tolerant bootstrap (the key safety property)
HerdR aborts a plugin install if its `[[build]]` command fails. So `bootstrap.sh`
**must not fail hard**: it installs every dependency it can, records per-dependency status
(installed / skipped:missing-prereq / degraded / incompatible) into state, and **exits 0**
for non-critical per-dependency failures. This is how "optional plugin failure must not
make HerdR unusable" and "headless must degrade gracefully" are guaranteed.

### D3 — The lock is the source of truth
`config/bundle.lock.json` pins, per dependency: repo, **pinned commit SHA**, version,
min_herdr_version, platforms, toolchain prereqs, license, enabled-by-default, security
notes, and verification date. The bootstrap never follows upstream HEAD. `jq` is used to
read it and to emit machine-readable doctor output for Ansible/CI.

### D4 — Ownership-aware, idempotent config
Powerpack-owned settings live under `HERDR_PLUGIN_CONFIG_DIR` (per-plugin, isolated) and a
Powerpack-managed overlay, tagged with an ownership marker. User-owned HerdR config
(`~/.config/herdr/config.toml`) and other plugins are **never touched**. Reconcile is
idempotent (installing an already-installed, correctly-pinned plugin is a no-op; HerdR's
own "reinstall replaces managed checkout" handles refresh).

### D5 — Environment detection drives enablement
`detect_env` records OS (linux/darwin), arch, HerdR version, and available tools
(bun/go/cargo/node/gh/git/agent-browser/chromium). A dependency is installed only if its
`platforms` include the OS **and** its `min_herdr_version` ≤ current **and** its toolchain
prereqs are present. Otherwise it is recorded as skipped/degraded — never a hard error.

### D6 — Roamgate is the mobile surface; private-by-default
Roamgate defaults to `127.0.0.1:8787`. The Powerpack keeps that default and, when
Tailscale is present, documents/reports the tailnet access path (loopback + tailnet/SSH
tunnel or a tailnet-bound bind with `ROAMGATE_PASSWORD`). It never opens a public bind.

### D7 — GitHub plugins degrade, not fail
`herdr-gh-checks` and `herdr-pr-board` are installed by default but the doctor reports
**degraded** (not failed) when `gh` is unauthenticated.

### D8 — Plannotator is HOLD, not ADOPT
`official.plannotator` currently cannot work (hard-coded `official.browser` dependency on
a deprecated plugin). It is recorded in the lock as `enabled:false` with a promotion note.
No fork, no fake integration.

## Runtime model

```
herdr plugin install berlinguyinca/herdr-powerpack
   └─ [[build]] scripts/bootstrap.sh          (no server; best-effort; exit 0)
         detect env → read bundle.lock.json → for each ADOPT/OPTIONAL dep:
            prereqs ok? → herdr plugin install <repo> --ref <sha> -y
            else → record skipped/degraded
         ownership-aware config defaults (idempotent)
         write state/reconcile.json (matrix)
   └─ [[startup]] scripts/reconcile.sh         (per server start; light verify)
         verify installed deps still present/enabled; refresh state; no side effects
   └─ [[actions]] doctor|status|versions|reconcile|update|repair|rollback|uninstall-clean
   └─ [[panes]]  board                          (human capability/health matrix)
```

## Manifest (Powerpack)

```toml
id = "berlinguyinca.powerpack"
name = "HerdR Powerpack"
version = "0.1.0"
min_herdr_version = "0.8.2"      # highest min among adopted deps (terminal-browser)
platforms = ["linux", "macos"]

[[build]]   command = ["bash", "scripts/bootstrap.sh"]
[[startup]] command = ["bash", "scripts/reconcile.sh"]

[[actions]] id="doctor" …            # scripts/doctor.sh (human + --json)
[[actions]] id="status" …
[[actions]] id="versions" …
[[actions]] id="reconcile" …
[[actions]] id="update" …            # preflight → snapshot → update → smoke → accept|rollback
[[actions]] id="repair" …
[[actions]] id="rollback" …
[[actions]] id="uninstall-clean" …   # remove powerpack-owned glue + managed deps (optional)

[[panes]] id="board" title="Powerpack" placement="popup" command=["bash","scripts/board.sh"]
```

## Directory layout
```
herdr-powerpack/
  herdr-plugin.toml
  README.md
  LICENSE (MIT)
  PROGRESS.md
  config/
    bundle.lock.json          # source of truth (pinned SHAs)
    powerpack.defaults        # powerpack-owned config overlay (ownership-tagged)
  scripts/
    common.sh                 # env detection, herdr bin, state helpers, logging/redaction
    bootstrap.sh              # build hook
    reconcile.sh              # startup hook + reconcile action
    doctor.sh                 # health matrix (human + --json)
    update.sh                 # update lifecycle (preflight/snapshot/smoke/accept)
    rollback.sh               # restore known-good
    board.sh                  # pane UI
  docs/
    architecture.md
    upstream-audit.md
    security.md
    troubleshooting.md
  ansible/
    roles/powerpack/…         # prereqs, ensure herdr, install pinned release, reconcile, doctor
  tests/
    run-tests.sh              # harness (uses herdr plugin link against a temp HOME)
    *.bats or *.sh            # the 14 acceptance scenarios
```

## Security posture (see docs/security.md)
- Pinned SHAs; license/provenance inventory in the lock.
- Install-hook review: each adopted dep's `[[build]]`/`[[startup]]` is recorded in the
  lock with a one-line summary; the doctor surfaces it.
- Secrets: Roamgate password / Telegram token are read from `HERDR_PLUGIN_CONFIG_DIR`
  (chmod 600), **never** logged or shown; doctor redacts.
- No public CDP/dev ports: browser attaches/launches locally; Roamgate defaults loopback.
- Unsafe-listener check: doctor reports any non-loopback HerdR/web listeners as warnings.
