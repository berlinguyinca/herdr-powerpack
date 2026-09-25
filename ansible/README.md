# Ansible deployment

Deploy the HerdR Powerpack to the whole fleet (Linux + macOS), **host-agnostic** —
no host names are hard-coded; the role keys off `ansible_os_family` /
`ansible_architecture`, so it works on `fry`, `beast`, `bender`, `macbook-m4`, or
any host group, and slots into an existing Ansible project.

```
# from the existing inventory, targeting any group:
ansible-playbook -i <inventory> ansible/playbook.yml
```

## What the role does
1. **Prereqs** — installs `git`, `curl`, `jq` (per OS family). Optionally installs
   `go` (pr-board) and/or `bun` (roamgate) via `powerpack_prereq_go` /
   `powerpack_prereq_bun`.
2. **Install** — ensures `herdr` (if `powerpack_install_herdr`, via the official
   `https://herdr.dev/install.sh` installer, or a pinned `powerpack_herdr_url` for
   reproducible deploys), then installs the Powerpack at `powerpack_repo` /
   `powerpack_ref` (client-side, socket-less, idempotent).
3. **Verify** — writes the owned `enable.list` (optional capabilities), runs the
   Powerpack `reconcile` (self-heal, enforces the private mobile bind), then runs
   `doctor --json`. With `powerpack_strict_doctor: true` it fails the playbook on
   a critical doctor finding.

## Reproducibility
Pin a release so deploys are identical across hosts:
```yaml
# group_vars/all.yml
powerpack_ref: <full-commit-sha-of-the-powerpack-release>
```

## Headless nodes
Headless hosts report the GUI capabilities (browser, desktop notifications) as
**degraded** in doctor — that is expected, graceful degradation, not an error.
Keep `powerpack_strict_doctor: false` there, or target a headless group with that
override:
```
ansible-playbook -i <inventory> ansible/playbook.yml --limit headless \
  --extra-vars 'powerpack_strict_doctor=false'
```

## Mobile access (private-by-default)
The mobile surface binds to **loopback** by default (`powerpack_mobile_bind:
loopback`). For tailnet access set `powerpack_mobile_bind: tailscale` (the role
enforces it via the Powerpack). Only set `lan` if you also configure a strong
`ROAMGATE_PASSWORD`; never expose the mobile surface publicly.

## Variables
See `roles/herdr-powerpack/defaults/main.yml` and `group_vars/all.yml`.
