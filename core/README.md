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
- macfanctld fan control (Mac hardware)
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

## disable-rsyslog.yml

Stop rsyslog from duplicating journal logs to `/var/log/syslog`

```bash
ansible-playbook core/disable-rsyslog.yml
```

journald already retains logs (see `agent-base.yml`'s journald configuration above), so rsyslog's copy in `/var/log/{syslog,auth.log,kern.log}` is redundant and just consumes extra disk space. This playbook stops and disables `rsyslog.service`, then stops and masks `syslog.socket` (which is `static`, so it cannot be `disable`d — only masking persists across reboots). After this, journald has no syslog consumer and `/var/log/syslog`, `/var/log/auth.log`, etc. stop growing. The journal itself is unaffected.

It also deletes the now-stale `/var/log/{syslog,auth.log,kern.log}*` files (including rotations). `/var/log/cloud-init.log` is left alone — it is written by cloud-init directly, not rsyslog.

To revert, unmask the socket and re-enable rsyslog:

```bash
sudo systemctl unmask syslog.socket
sudo systemctl enable --now rsyslog.service
```

## x11vnc.yml

VNC server with virtual framebuffer (Xvfb) setup (optional)

```bash
ansible-playbook core/x11vnc.yml
```

Unlike Mac screen sharing, this does **not** connect to the Ubuntu login screen or physical display. It creates an independent virtual framebuffer (Xvfb) that exists only in memory.

Configures x11vnc as a user-level systemd service:
- Runs as your user (not root) for better security
- VNC password stored in `~/.vnc/passwd`
- Startup script: `~/.vnc/start-x11vnc.sh` (can be run standalone)
- Service managed via `systemctl --user` commands
- Disables Wayland (X11 required for x11vnc)
- Systemd lingering enabled (service persists after logout)

Manage the service:
```bash
systemctl --user start x11vnc      # Start VNC server
systemctl --user stop x11vnc       # Stop VNC server
systemctl --user status x11vnc     # Check status
journalctl --user -u x11vnc -f     # View logs
```

Test manually (without systemd):
```bash
~/.vnc/start-x11vnc.sh
```

Test the virtual display:
```bash
xcalc &
```

**Note:** Snap-based apps (e.g. Firefox) are slow to launch inside the Xvfb session due to snap confinement overhead. Prefer native `.deb` packages for apps you intend to run over VNC.

## samba.yml

Samba file sharing setup (home directory share)

```bash
SAMBA_PASSWORD=<password> ansible-playbook core/samba.yml
```

Moved here from the retired `services/` directory: sharing your own home directory over SMB
is a workstation function, not a hosted service. See [Retired: `services/`](../README.md#retired-services).

**Environment variables** (see [`env-tmpl.sh`](env-tmpl.sh)):

| Variable | Required | Description |
|----------|----------|-------------|
| `SAMBA_PASSWORD` | Yes | Samba password for the current user |
| `SAMBA_INTERFACES` | No | Network interfaces to bind (e.g. `lo eth0`). If unset, Samba listens on all interfaces |

This playbook:
- Installs Samba
- Sets the Samba password for the current user
- Configures a `[homes]` share (not browseable, read-write, `valid users = %S` so only the owner can open it)
- Optionally restricts Samba to specific network interfaces via `SAMBA_INTERFACES`
- Enables and starts `smbd` and `nmbd`

**Connecting from macOS:**

In Finder, press `⌘K` and enter:
```
smb://<host-ip>
```

**Managing the service:**
```bash
systemctl status smbd nmbd    # Check status
systemctl restart smbd nmbd   # Restart
journalctl -u smbd -f         # View logs
```

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
