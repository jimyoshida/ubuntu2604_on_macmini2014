# ubuntu2604_on_macmini2014

This directory contains Ansible playbooks for automated Ubuntu 26.04 agent environment setup.

## Prerequisites

Ubuntu 26.04 with system packages up to date and Ansible 2.20 installed:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ansible
```

## Ubuntu Agent Base Setup

Use the Ansible playbooks in this directory for automated setup.

### Passwordless Sudo Setup

For a smoother experience, especially on Ubuntu 26.04+, configure passwordless sudo first:

```bash
./setup-passwordless-sudo.sh
```

This eliminates the need for `-K` (or `--ask-become-pass`) flags and avoids sudo prompt compatibility issues with newer Ubuntu versions.

### Core System Setup

#### agent-base.yml

General agent base setup (SSH, Samba, Avahi)

```bash
ansible-playbook core/agent-base.yml
```

This playbook configures:
- Hostname and network settings
- SSH server with keep-alive (12h sessions)
- Samba with home directory sharing
- Avahi daemon for mDNS
- System sleep/suspend/lid handling disabled
- Keychain for SSH key management
- X11 permissions for container access
- Git branch display in bash prompt

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

#### nvm.yml

Node.js LTS installation via nvm

```bash
ansible-playbook core/nvm.yml
```

Installs nvm (Node Version Manager) and the latest Node.js LTS version. Required for OpenClaw.

Common nvm commands:
```bash
nvm ls                  # List installed versions
nvm install --lts       # Install latest LTS
nvm use --lts           # Use LTS version
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

### Cloud CLI Tools

#### aws-cli.yml

Install AWS CLI

```bash
ansible-playbook cloud-cli/aws-cli.yml
```

#### azure-cli.yml

Install Azure CLI

```bash
ansible-playbook cloud-cli/azure-cli.yml
```

#### gcloud-cli.yml

Install Google Cloud CLI

```bash
ansible-playbook cloud-cli/gcloud-cli.yml
```

### K8s Tools

#### kubectl.yml

Install kubectl (Kubernetes CLI)

```bash
ansible-playbook k8s/kubectl.yml
```

Includes bash completion and `k` alias.

#### helm.yml

Install Helm (Kubernetes package manager)

```bash
ansible-playbook k8s/helm.yml
```

Includes bash completion.

#### krew.yml

Install Krew (kubectl plugin manager)

```bash
ansible-playbook k8s/krew.yml
```

After installation, install common plugins:
```bash
kubectl krew install ctx ns node-shell
```

### AI Agent Tools

#### openclaw.yml

OpenClaw Slack agent setup

```bash
ansible-playbook ai-agent/openclaw.yml
```

**Prerequisites:**
- Run `nvm.yml` first to install Node.js LTS
- Slack App Token and Bot Token (see below for setup instructions)

This playbook:
- Installs OpenClaw globally via npm (`npm install -g openclaw@latest`)
- Creates environment file for Slack integration
- **Does NOT automatically run onboarding** - manual steps required (see below)

**How to obtain Slack tokens:**

1. **Create a Slack App:**
   - Go to https://api.slack.com/apps
   - Click **"Create New App"** → **"From scratch"**
   - Name it (e.g., "OpenClaw") and select your workspace

2. **Enable Socket Mode (for App Token):**
   - Go to **"Socket Mode"** under Settings
   - Enable Socket Mode
   - Create app-level token with scope: `connections:write`
   - Copy the token → this is your **`SLACK_APP_TOKEN`** (starts with `xapp-`)

3. **Configure Bot Token:**
   - Go to **"OAuth & Permissions"** under Features
   - Add **"Bot Token Scopes"**:
     - `chat:write`, `files:write`
     - `channels:history`, `groups:history`, `im:history`, `mpim:history`
     - `app_mentions:read`
   - Click **"Install to Workspace"** and authorize
   - Copy **"Bot User OAuth Token"** → this is your **`SLACK_BOT_TOKEN`** (starts with `xoxb-`)

4. **Enable Event Subscriptions:**
   - Go to **"Event Subscriptions"** under Features
   - Toggle **"Enable Events"** to On
   - Subscribe to bot events: `message.channels`, `message.groups`, `message.im`, `message.mpim`, `app_mention`

**Manual Onboarding Steps (Required):**

After running the playbook, open a new shell and complete the onboarding manually:

```bash
openclaw onboard --install-daemon
sudo loginctl enable-linger $USER
```

The onboarding command:
- Installs the OpenClaw systemd service (`openclaw-gateway.service`)
- Configures the daemon to run at startup
- Sets up the necessary permissions and environment

After manual onboarding, manage the service:
```bash
systemctl --user start openclaw-gateway      # Start
systemctl --user status openclaw-gateway     # Check status
journalctl --user -u openclaw-gateway -f     # View logs
systemctl --user stop openclaw-gateway       # Stop
```

**Manual usage without daemon:**
```bash
openclaw gateway --port 18789 --verbose
openclaw message send --target <number> --message "Hello"
openclaw agent --message "Your query" --thinking high
```

**Updating OpenClaw:**
```bash
npm update -g openclaw
```

Documentation: https://docs.openclaw.ai/

#### claude-code.yml

Install Claude Code CLI

```bash
ansible-playbook ai-agent/claude-code.yml
```

Installs the Claude Code CLI tool using the official installation script. The playbook:
- Installs prerequisites (curl, ca-certificates)
- Downloads and runs the official Claude Code installer
- Respects `HTTPS_PROXY` environment variable
- Verifies installation and displays version

After installation, authenticate with:
```bash
claude auth login
```

Documentation: https://claude.ai/code
