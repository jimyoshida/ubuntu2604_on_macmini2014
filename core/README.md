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

Also installs `avahi-utils`. Useful commands:

```bash
avahi-browse -a -t                          # Discover all mDNS services on the LAN (one-shot)
avahi-browse _ssh._tcp -t                   # Find SSH-advertised hosts
avahi-resolve-host-name hostname.local      # Resolve a .local hostname to IP
avahi-resolve-address 192.168.x.x          # Reverse-resolve IP to .local name
```

## ssh-key-setup.yml

SSH public key authentication setup

```bash
ansible-playbook core/ssh-key-setup.yml
```

This playbook configures SSH key permissions and authorized_keys after `id_rsa` and `id_rsa.pub` have been uploaded to the machine. It:
- Sets proper permissions on `.ssh/` directory (700)
- Sets proper permissions on `id_rsa` private key (600)
- Sets proper permissions on `id_rsa.pub` public key (644)
- Creates and configures `authorized_keys` file (600)
- Appends public key to authorized_keys if not already present
- Validates key files exist before processing

Run this playbook after `agent-base.yml` to complete SSH setup for remote access.

## samba.yml

Samba file sharing setup (optional)

```bash
ansible-playbook core/samba.yml
```

Only needed if you require Windows file sharing (SMB/CIFS) for home directory access over the network. Not required for typical development workflows.

Configures Samba with home directory sharing:
- Installs and enables Samba (smbd, nmbd)
- Sets Samba password for the current user
- Creates [homes] share with secure permissions (0700)
- Optional interface binding for multi-network setups

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

## homebrew.yml

Install Homebrew package manager

```bash
ansible-playbook core/homebrew.yml
```

After installation, use Homebrew to install additional tools:
- K9s, KDash

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

## golang.yml

Install Go (Golang) programming language

```bash
ansible-playbook core/golang.yml
```

Installs Go from the official Go binary distribution with minimal dependencies. The playbook:
- Downloads the official Go tarball from go.dev
- Extracts to `/usr/local/go`
- Adds Go to PATH and sets up GOPATH in `~/.bashrc`
- Supports version upgrades by updating the `go_version` variable

After installation, activate in current shell:
```bash
source ~/.bashrc
go version
```

## rust.yml

Install Rust programming language

```bash
ansible-playbook core/rust.yml
```

Installs Rust via rustup (official Rust toolchain installer) with minimal dependencies. The playbook:
- Downloads and runs the official rustup installer from sh.rustup.rs
- Installs the stable toolchain to `~/.cargo`
- Adds Cargo bin directory to PATH in `~/.bashrc`
- Includes rustc (compiler) and cargo (package manager)

After installation, activate in current shell:
```bash
source ~/.bashrc
rustc --version
cargo --version
```

Common post-install steps:
```bash
rustup component add clippy rustfmt  # Add linter and formatter
```

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
