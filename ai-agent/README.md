# AI Agent Tools

## openclaw.yml

OpenClaw Slack agent setup

```bash
ansible-playbook ai-agent/openclaw.yml
```

**Prerequisites:**
- System-wide Node.js installed via apt: `sudo apt install nodejs npm`
  - mise/nvm-managed Node.js will cause the playbook to fail

This playbook:
- Installs OpenClaw globally via npm (`npm install -g openclaw@latest`)
- Sets up shell completion (bash/zsh/fish)
- **Does NOT automatically run onboarding** - manual steps required (see below)

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

## nanoclaw.yml

NanoClaw agent setup (Docker-based, lightweight OpenClaw alternative)

```bash
ansible-playbook ai-agent/nanoclaw.yml
```

**Prerequisites:**
- Docker installed and current user in the `docker` group:
  ```bash
  ansible-playbook container/docker.yml
  ```
  The playbook will fail with a clear message if Docker is missing or the user is not in the `docker` group.

This playbook:
- Installs `build-essential`, `python3`, `curl`, `git` via apt
- Clones `https://github.com/nanocoai/nanoclaw.git` to `~/nanoclaw`
- Enables systemd lingering
- **Does NOT run the interactive installer** — manual steps required (see below)

**Manual Onboarding Steps (Required):**

After running the playbook, open a new shell and run:

```bash
cd ~/nanoclaw
bash nanoclaw.sh
```

The installer handles:
- Node 22 via nvm and pnpm 10 via corepack
- Building the agent container image
- Registering your Anthropic API key with OneCLI vault
- Pairing a messaging channel (Slack, WhatsApp, Telegram, etc.)
- Installing the `nanoclaw-v2-<slug>` systemd user service

After onboarding, manage the service (replace `<slug>` with your agent slug):
```bash
systemctl --user start nanoclaw-v2-<slug>     # Start
systemctl --user status nanoclaw-v2-<slug>    # Check status
journalctl --user -u nanoclaw-v2-<slug> -f   # View logs
systemctl --user stop nanoclaw-v2-<slug>      # Stop
```

**Troubleshooting:**
```bash
# sqlite3 build failure
cd ~/nanoclaw && pnpm rebuild better-sqlite3

# Container build issue
cd ~/nanoclaw && docker builder prune -f && ./container/build.sh
```

Installer log: `~/nanoclaw/logs/setup.log`
Service error log: `~/nanoclaw/logs/nanoclaw.error.log`

**Updating NanoClaw:**
```bash
cd ~/nanoclaw && git pull && bash nanoclaw.sh
```

Documentation: https://docs.nanoclaw.dev/

---

## vertex-ai-proxy.yml

Install vertex-ai-proxy and run it as a user-level systemd service

```bash
ansible-playbook ai-agent/vertex-ai-proxy.yml
```

**Prerequisites:**
- System-wide Node.js installed via apt: `sudo apt install nodejs npm`
  - mise/nvm-managed Node.js will cause the playbook to fail

This playbook:
- Installs `vertex-ai-proxy` globally via npm
- Creates `~/.config/systemd/user/vertex-ai-proxy.service`
- Enables systemd lingering so the service survives logout
- Enables and starts the service immediately

**Required setup before starting the service:**

`vertex-ai-proxy config` must be run once to configure the proxy (Google Cloud project, credentials, etc.) before the systemd service will work:

```bash
vertex-ai-proxy config
```

Also ensure gcloud ADC credentials are valid:
```bash
gcloud auth application-default login
```

**Managing the service:**
```bash
systemctl --user status vertex-ai-proxy   # Check status
systemctl --user restart vertex-ai-proxy  # Restart
journalctl --user -u vertex-ai-proxy -f   # View logs
systemctl --user stop vertex-ai-proxy     # Stop
```

## gemini-cli.yml

Install Gemini CLI

```bash
ansible-playbook ai-agent/gemini-cli.yml
```

**Prerequisites:**
- System-wide Node.js installed via apt: `sudo apt install nodejs npm`
  - mise/nvm-managed Node.js will cause the playbook to fail
- `gcloud` CLI installed and authenticated

This playbook:
- Installs `@google/gemini-cli` globally via npm
- Sets `GOOGLE_GENAI_USE_VERTEXAI=true` in `.bashrc`

**Required setup before use:**

Authenticate with Google Cloud ADC so Gemini CLI can access Vertex AI:

```bash
gcloud auth application-default login
```

Also ensure the target project has the Vertex AI API enabled:

```bash
gcloud services enable aiplatform.googleapis.com --project $GOOGLE_CLOUD_PROJECT
```

**Usage:**

```bash
gemini
```

**Updating Gemini CLI:**
```bash
sudo npm update -g @google/gemini-cli
```

Documentation: https://github.com/google-gemini/gemini-cli

## claude-code.yml

Install Claude Code CLI

```bash
ansible-playbook ai-agent/claude-code.yml
```

Installs the Claude Code CLI tool using the official installation script. The playbook:
- Installs prerequisites (curl, ca-certificates)
- Downloads and runs the official Claude Code installer
- Ensures `~/.local/bin` is added to PATH in both `.bashrc` and `.profile`
- Respects `HTTPS_PROXY` environment variable
- Verifies installation and displays version

After installation, authenticate with:
```bash
claude auth login
```

Documentation: https://claude.ai/code
