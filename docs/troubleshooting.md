# Troubleshooting

The first tool for any Powerpack question is the doctor:

```bash
herdr plugin action invoke berlinguyinca.powerpack.doctor      # human matrix
scripts/doctor.sh --json                                       # machine-readable
scripts/doctor.sh --json --strict                              # CI gate (exit 1 on critical)
scripts/versions.sh                                            # locked vs installed
```

Each capability row shows `STATUS` (installed / optional / skipped / held / missing /
failed) and `HEALTH` (healthy / degraded / missing / held), plus a NOTE.

## A capability shows `skipped`
A skipped capability was not installed because a precondition was not met. The NOTE says
why:
- `missing-prereq:<tool>` — a required toolchain is absent (e.g. `roamgate` needs `bun`).
  Install the tool and re-run `reconcile`, or (for `bun`) allow auto-install by not
  setting `POWERPACK_AUTO_PREREQS=0`.
- `platform:<os> unsupported` — the dependency does not support this OS.
- `incompatible-herdr (need >=X, have Y)` — upgrade Herdr or the dependency is not
  installable on this version.
- `not-selected` — an optional capability that is disabled by default.

## A capability shows `failed`
The install command for that dependency failed (network, build, or the upstream's build
hook). Check the NOTE for the last error line. Re-run
`herdr plugin action invoke berlinguyinca.powerpack.reconcile` to retry. This does **not**
affect the rest of the bundle (failure isolation).

## A capability shows `missing` (but it is a default)
The dependency is expected but not currently installed (e.g. uninstalled by hand). Re-run
`reconcile` to self-heal: `herdr plugin action invoke berlinguyinca.powerpack.reconcile`.

## `degraded` GitHub capabilities (gh-checks / pr-board)
These need `gh` authentication. When unauthenticated they install fine but report
`degraded` with NOTE `gh not authenticated`. Run `gh auth login` to make them fully
functional. This is by design — the bundle stays usable without GitHub auth.

## Headless nodes
On a headless box the browser and desktop-notification capabilities are expected to be
**degraded** (no display / no notification daemon). This is graceful degradation, not an
error. The bundle's non-GUI capabilities (swarm, worktrees, GitHub, mobile-over-Tailscale)
still work. `doctor --strict` will flag missing *default* GUI capabilities; use it only
where those are expected.

## Mobile / Roamgate not reachable
- Confirm Roamgate is installed: `doctor` row for `roamgate` should be `installed` (needs
  `bun`).
- Roamgate binds to `127.0.0.1:8787` by default. From the host, open
  `http://127.0.0.1:8787`. From the tailnet, reach the host's loopback via Tailscale
  (route/SSH tunnel) — do not expose the port publicly.
- `doctor` warns if it sees a **non-loopback** listener on 8787/CDP ports; review that
  before relying on the host.

## Reinstall / update a specific dependency
```bash
herdr plugin action invoke berlinguyinca.powerpack.update      # snapshot + re-pin all
herdr plugin action invoke berlinguyinca.powerpack.rollback    # restore last snapshot
```

## Uninstalling
`herdr plugin uninstall berlinguyinca.powerpack` removes the Powerpack's managed checkout
and registration. It does **not** remove unrelated plugins or user data. Managed upstream
plugins remain installed unless you explicitly uninstall them (or use a future
`uninstall-clean` that removes only Powerpack-managed ones). Your `~/.config/herdr`
configuration is never touched by the Powerpack.

## Isolated / hermetic testing
```bash
tests/run-tests.sh            # runs everything in a temp HOME; your real Herdr is untouched
tests/run-tests.sh --keep     # keep the temp HOME for inspection
```
