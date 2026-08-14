# Core System Setup

## core-tools.yml

Install common CLI packages (git, jq, compression tools, etc.)

```bash
ansible-playbook core/core-tools.yml
```

Installs one fixed list of packages: `net-tools`, `ncat`, `ca-certificates`, `curl`,
`gnupg`, `lsb-release`, `git`, `git-lfs`, `git-secret`, `python3-pip`, `jq`, `zip`, `unzip`,
`vim`, `figlet`, `cowsay`, `make`, `dos2unix`, `aha`. Nothing else — no shell configuration, no
service, no per-account state.

Renamed from `core/agent-base.yml` (2026-08-14). That playbook used to also configure SSH,
Avahi, systemd logind, journald, and the hostname/IPv6 settings that needed `core/env-tmpl.sh`;
all of it was removed over a series of cuts earlier the same day, none of it being something an
AI coding agent needs done on every run, until only the package list was left. The cuts changed
too much of the file for git to detect the rename on its own, so `--follow` won't cross the
boundary; see git history on both paths instead
(`git log --all --full-history -- core/agent-base.yml core/core-tools.yml`) for the tasks that
used to be here. On an AWS EC2 target the removed tasks are mostly redundant with what the AMI
and cloud-init already do; on a physical PC they generally still need doing by hand — see
[PHYSICAL-HOST-SETUP.md](../PHYSICAL-HOST-SETUP.md) for the manual equivalent of each one.

## nodejs.yml

Install Node.js LTS system-wide (via NodeSource)

```bash
ansible-playbook core/nodejs.yml
```

Installs Node.js LTS via the official NodeSource APT repository. Required for OpenClaw.

Common commands:
```bash
node --version          # Show Node.js version
npm --version           # Show npm version
npm install -g <pkg>    # Install a global package
```

## mise.yml

Install mise (polyglot runtime version manager)

```bash
ansible-playbook core/mise.yml
```

Installs mise via the official APT repository for managing language runtimes (Python, Ruby, etc.).

Common mise commands:
```bash
mise ls                        # List installed runtimes
mise use --global python@3.12  # Install and set Python globally
mise ls-remote python          # List available Python versions
```

The Go and Rust toolchains used to be installed here, by `golang.yml` and `rust.yml`. Both were
retired on 2026-08-10 — see
[Retired: `core/golang.yml` and `core/rust.yml`](../README.md#retired-coregolangyml-and-corerustyml).
`mise.yml` above is the general-purpose replacement for a per-account runtime.

---

## chrony (NTP) — Ubuntu 26.04 default (no playbook needed)

Ubuntu 26.04 ships chrony pre-installed, enabled, and well-configured. No playbook is needed. Before 26.04, chrony had to be installed and configured manually.

Default configuration highlights:
- NTS (Network Time Security) enabled — authenticated NTP over TLS, unlike plain NTP used in older setups
- Time sources: Canonical's NTP pool (`ntp.ubuntu.com`, Stratum 2)
- `makestep 1 3` — steps the clock on large initial offsets at boot instead of slewing slowly
- `rtcsync` — syncs hardware clock every 11 minutes

Check sync status:
```bash
chronyc tracking    # Current sync status and offset
chronyc sources -v  # Active time sources
```
