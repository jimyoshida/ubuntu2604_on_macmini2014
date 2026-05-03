# Core System Setup

#### agent-base.yml

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
- `s` alias for `systemctl`

#### samba.yml

Samba file sharing setup

```bash
ansible-playbook core/samba.yml
```

This playbook configures:
- Samba with home directory sharing
- Optional interface binding

#### podman.yml

Podman container runtime setup

```bash
ansible-playbook core/podman.yml
```

This playbook configures:
- Podman and podman-compose from the Ubuntu default repository
- Loginctl lingering for rootless containers (survive logout)
- X server access for containers

#### docker.yml

Docker Engine setup

```bash
ansible-playbook core/docker.yml
```

This playbook configures:
- Docker GPG key and repository
- Docker Engine, CLI, and containerd
- Docker buildx plugin and docker-compose plugin
- User group permissions for non-root Docker access

#### x11vnc.yml

VNC server setup (optional)

```bash
ansible-playbook core/x11vnc.yml
```

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

#### homebrew.yml

Install Homebrew package manager

```bash
ansible-playbook core/homebrew.yml
```

After installation, use Homebrew to install additional tools:
- kind (Kubernetes in Docker)
- K9s, KDash

#### mise.yml

Install mise (polyglot runtime version manager)

```bash
ansible-playbook core/mise.yml
```

Installs mise via the official APT repository and installs Node.js LTS. Required for OpenClaw.

Common mise commands:
```bash
mise ls                        # List installed runtimes
mise use --global node@lts     # Install and set Node.js LTS globally
mise use --global node@22      # Install and set a specific version
mise ls-remote node            # List available Node.js versions
```

#### golang.yml

Install Go (Golang) programming language

```bash
ansible-playbook core/golang.yml
```

Installs Go from the official Go binary distribution with minimal dependencies. The playbook:
- Downloads the official Go tarball from go.dev
- Extracts to `/usr/local/go`
- Adds Go to PATH and sets up GOPATH in `~/.bashrc`
- Respects `HTTPS_PROXY` environment variable
- Supports version upgrades by updating the `go_version` variable

After installation, activate in current shell:
```bash
source ~/.bashrc
go version
```

#### rust.yml

Install Rust programming language

```bash
ansible-playbook core/rust.yml
```

Installs Rust via rustup (official Rust toolchain installer) with minimal dependencies. The playbook:
- Downloads and runs the official rustup installer from sh.rustup.rs
- Installs the stable toolchain to `~/.cargo`
- Adds Cargo bin directory to PATH in `~/.bashrc`
- Respects `HTTPS_PROXY` environment variable
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
