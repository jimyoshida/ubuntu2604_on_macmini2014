# Core System Setup

## agent-base.yml

General agent base setup (SSH, Avahi)

```bash
ansible-playbook core/agent-base.yml
```

This playbook configures:
- Hostname and network settings
- SSH server with keep-alive (12h sessions)
- Avahi daemon for mDNS
- systemd-resolved for DNS
- System sleep/suspend/lid handling disabled
- Screen blanking and GNOME lock disabled
- Keychain for SSH key management
- Git branch display in bash prompt
- `s` alias for `systemctl --user`
- IPv6 disabled on the specified NetworkManager connection
- journald low disk I/O configuration (500MB max, 3-day retention, 5-minute sync intervals)

Also installs `avahi-utils`. Useful commands:

```bash
avahi-browse -a -t                          # Discover all mDNS services on the LAN (one-shot)
avahi-browse _ssh._tcp -t                   # Find SSH-advertised hosts
avahi-resolve-host-name hostname.local      # Resolve a .local hostname to IP
avahi-resolve-address 192.168.x.x          # Reverse-resolve IP to .local name
```

This playbook configures the SSH **server**. The client-side half — permissions on your own
`~/.ssh` and your key in `authorized_keys` — is not a playbook: it needs no privileges and no
remote connection, so it is [`setup-passwordless-ssh.sh`](../setup-passwordless-ssh.sh) instead
(see [Passwordless SSH Setup](../README.md#passwordless-ssh-setup)). Run that after this
playbook to finish SSH setup for remote access.

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
