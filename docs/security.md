# Security & Supply-Chain Posture

Every HerdR plugin is **third-party code that runs as the user** with full access to the
HerdR CLI. The Powerpack treats its managed dependencies accordingly.

## Threat model
- A managed dependency is untrusted code + a build hook that runs at install time.
- The Powerpack's job is to constrain that surface: pin exact revisions, inventory
  provenance/permissions, detect unsafe network exposure, and keep secrets out of logs/UI.

## Pinning & provenance
- `config/bundle.lock.json` pins each dependency by **full commit SHA** and records its
  **license**, **platforms**, **min_herdr_version**, **install hook**, and a
  **verification date**. The lock is the deployment source of truth; upstream `HEAD` is
  never followed.
- The Powerpack never performs "arbitrary marketplace auto-install": it only installs the
  repos enumerated in the lock, at their pinned SHAs.

## Install-hook / permission inventory
Recorded per-dependency in the lock (`install_hook`, `startup_hook`, `security_notes`).
Summary of the default bundle:

| Dependency | Install hook | Network at install | Runtime exposure |
| --- | --- | --- | --- |
| `structupath.browser` | none (bash) | git clone | attaches to / launches a **local** Chromium; no public CDP port by default |
| `roamgate` | downloads **checksum-verified** prebuilt binary | git clone + release download | **loopback by default** (127.0.0.1:8787) |
| `structupath.swarm` | none (bash+git) | git clone | none |
| `serhii-chernenko.worktreeinclude` | none (bash+git) | git clone | none |
| `jonasbaeumer.file-annotator` | fetch-or-build: release tarball, **SHA-256 verified**, cargo fallback | git clone + release download | none persistent |
| `herdr-gh-checks` | fetch-or-build: prebuilt Go binary, **SHA-256 verified**, go build fallback | git clone + release download | reads CI via `gh`; none persistent |
| `cdowell09.pr-board` | `go build` | git clone | reads via `gh` |
| `quinnjr.herdr-notifications` | `cargo build --release` | git clone | native OS notifications only; no network |

Optional: `barnuri/herdr-notifications` (Telegram) requires a **bot token** (secret) +
outbound network; disabled by default. `zenbu-labs/terminal-browser` downloads via an
install script (Electron).

## Network binding (private-by-default)
- **Roamgate** binds to `127.0.0.1:8787` by default. The Powerpack **never** opens a
  public bind. The intended private path is `phone → Tailscale → host → Roamgate
  (loopback)`. For tailnet access, either keep loopback + tailnet route/SSH tunnel to
  loopback, or bind the tailnet interface **with** a strong `ROAMGATE_PASSWORD` + TLS.
- **Browser** attaches to an existing CDP endpoint or launches a local Chromium; it does
  not expose a public debug/CDP port by default.
- **Unsafe-listener check:** `doctor` scans listeners and warns on any **non-loopback**
  bind on the bundle's web/CDP ports (8787, 9222/9229/9230). It intentionally reports
  only bundle-relevant ports (not every system listener).

## Secrets
- Secrets (e.g. `ROAMGATE_PASSWORD`, a Telegram bot token) belong in the Powerpack config
  dir (chmod 600) or the environment — **never** in the lock, logs, doctor output, or the
  TUI.
- All diagnostics are passed through a redaction filter (GitHub tokens, bearer tokens,
  Telegram tokens, `ROAMGATE_PASSWORD=`).
- `gh` authentication state is reported as a boolean only; no tokens are read or shown.

## Failure isolation
- The bootstrap build hook is **best-effort** and always exits 0 for non-critical
  per-dependency failures, so one failing optional dependency can never make Herdr
  unusable.
- A missing toolchain (e.g. `bun`) degrades a capability to *skipped*, not *failed*.

## Update review
- On update, the Powerpack re-pins each dependency at its **locked** SHA (not upstream
  HEAD) and (Phase 3) preflights for manifest/install-hook/permission changes before
  accepting, rolling back to the last snapshot on a critical failure.
