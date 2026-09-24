# HerdR Powerpack

A **thin HerdR meta-plugin / distribution**. One install gives a HerdR
installation a curated, tested capability bundle by **adopting existing upstream
HerdR plugins** — never re-implementing them.

```
herdr plugin install berlinguyinca/herdr-powerpack
```

The Powerpack stays thin. It owns:

- **Dependency + version locking** — `config/bundle.lock.json` pins every upstream
  by commit SHA. The lock is the deployment source of truth; upstream `HEAD` is
  never followed.
- **Environment-aware bootstrap/reconcile** — detects OS/arch/HerdR version/toolchain
  and installs only what is compatible; everything else degrades gracefully.
- **Ownership-aware, idempotent config** — it never touches the user's HerdR config or
  other plugins; repeated reconcile is a no-op.
- **Health / doctor UX** — human and machine-readable (`--json`) capability matrix.
- **Update / rollback** — snapshot before update; restore known-good on failure.
- **Security checks** — provenance inventory, unsafe-listener detection, secret redaction.

## What it bundles (default)

Capability | Upstream (pinned) | Notes
--- | --- | ---
Browser (CDP/QA) | `StructuPath/herdr-browser` | real Chromium, local-site inspection, console/network errors, QA screenshots, observe-only/takeover
Mobile / web | `powerfooI/roamgate` | full desktop+mobile PWA client; **private-by-default** (loopback)
Swarm | `StructuPath/herdr-swarm` | worktree-per-agent fan-out, review-first harvest
Worktrees | `serhii-chernenko/herdr-worktreeinclude` | project-local worktrees + `.worktreeinclude`
File review | `JonasBaeumer/herdr-file-annotator` | agent-summoned blocking diff review (MCP)
GitHub / CI | `itisbryan/herdr-gh-checks`, `cdowell09/herdr-pr-board` | degrade (not fail) when unauthenticated
Desktop notifications | `quinnjr/herdr-notifications` | native OS notifications, no network (needs a working Rust toolchain)

Optional (disabled by default): `zenbu-labs/terminal-browser`, `barnuri/herdr-notifications`
(Telegram). Hold: `plannotator/herdr-plannotator` (see audit). Rejected: task/dispatch
plugins (competing state models / no license).

Full reasoning and every ADOPT/OPTIONAL/ADAPT/HOLD/REJECT decision: **[`docs/upstream-audit.md`](docs/upstream-audit.md)**.

## Powerpack-owned vs upstream

| Owned by the Powerpack | Owned by upstream |
| --- | --- |
| `herdr-plugin.toml`, `scripts/*.sh`, `config/bundle.lock.json` | `StructuPath/herdr-browser` |
| doctor / reconcile / update / rollback logic | `powerfooI/roamgate` |
| dependency selection + enablement | `StructuPath/herdr-swarm`, `…/herdr-worktreeinclude` |
| health matrix, unsafe-listener check | `JonasBaeumer/herdr-file-annotator` |
| provenance/security inventory | `itisbryan/herdr-gh-checks`, `cdowell09/herdr-pr-board`, `quinnjr/herdr-notifications` |

The Powerpack does **not** contain or re-implement any browser engine, remote-desktop
stack, Pi/Pi Web, `pi-engineering`, `autospec`, Plannotator, or GitHub client.

## Install

```bash
herdr plugin install berlinguyinca/herdr-powerpack
```

The install's build hook (`scripts/bootstrap.sh`) runs **best-effort**: it installs each
locked upstream at its pinned SHA and **never aborts** the Powerpack install on a
per-dependency failure. Missing toolchains (e.g. `bun`) cause a capability to be *skipped*
(degraded), not to fail the install.

Prerequisites: `bash`, `git`, `curl` (always); `jq` (for machine-readable doctor).
Per-capability toolchains are optional and detected: `node`, `bun`, `go`, `cargo`, `gh`.

### Doctor / status

```bash
herdr plugin action invoke berlinguyinca.powerpack.doctor          # human matrix
herdr plugin action invoke berlinguyinca.powerpack.versions        # locked vs installed
herdr plugin pane open --plugin berlinguyinca.powerpack --entrypoint board   # board pane
```

Machine-readable (for Ansible/CI):

```bash
scripts/doctor.sh --json          # full matrix as JSON
scripts/doctor.sh --json --strict # exit 1 if a default capability is missing/failed
```

## Update & rollback

```bash
herdr plugin action invoke berlinguyinca.powerpack.update     # snapshot + refresh pinned deps
herdr plugin action invoke berlinguyinca.powerpack.rollback   # restore last snapshot
herdr plugin action invoke berlinguyinca.powerpack.reconcile  # self-heal (re-add missing defaults)
```

There is no `herdr plugin update` in HerdR v1, so Powerpack "update" = snapshot the current
known-good set, re-pin every dependency at its locked SHA, and (Phase 3) gate on smoke
tests, rolling back automatically on a critical failure.

## Mobile / private access model

The mobile surface is **Roamgate**, which binds to **`127.0.0.1` by default** (port 8787).
The intended private path is:

```
phone / laptop  ──>  Tailscale (tailnet)  ──>  HerdR host  ──>  Roamgate (loopback)
```

The Powerpack **never** opens a public bind. For tailnet access, keep Roamgate on loopback
and reach it over Tailscale (SSH tunnel / tailnet route to loopback), or bind the tailnet
interface with a strong `ROAMGATE_PASSWORD` + TLS. `doctor` reports any non-loopback
listener on the bundle's web/CDP ports as a warning. See [`docs/security.md`](docs/security.md).

## Headless / multi-host

Linux and macOS. Headless nodes report unsupported/degraded GUI capabilities (browser,
desktop notifications) instead of failing the bundle. Deployment is designed for the
existing Ansible project (host-agnostic — no hard-coded host names); see `ansible/` and
[`docs/troubleshooting.md`](docs/troubleshooting.md).

## Repository layout

```
herdr-powerpack/
  herdr-plugin.toml        # current-format manifest
  config/bundle.lock.json  # pinned upstreams (source of truth)
  scripts/                 # thin bootstrap/reconcile/doctor/update/rollback glue (Bash)
  docs/                    # architecture, upstream-audit, security, troubleshooting
  ansible/                 # deployment role (Phase 5)
  tests/run-tests.sh       # acceptance test harness (isolated HOME)
```

## Development / tests

```bash
tests/run-tests.sh          # isolated, hermetic acceptance tests (no live browser needed)
```

## License

MIT — see [LICENSE](LICENSE). Upstream plugins retain their own licenses (inventoried in
`config/bundle.lock.json`).
