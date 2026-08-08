# AI Agent Tools

## nanoclaw.yml

NanoClaw agent setup (Docker-based, lightweight OpenClaw alternative)

```bash
ansible-playbook _personal/ai-agent/nanoclaw.yml
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
- Node 22 and pnpm 10 via corepack
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

**Using the `claw` CLI (optional):**

After onboarding, you can install the `claw` CLI to send prompts to the agent directly from the terminal — no chat app required. Open Claude Code in `~/nanoclaw` and run:

```
/claw
```

This installs `~/bin/claw` and symlinks it from the NanoClaw scripts. Then you can chat with the agent from any terminal:

```bash
claw "What's on my calendar today?"
claw --list-groups          # show registered groups
claw -g "dev" "Deploy status?"
cat report.txt | claw --pipe "Summarize this"
```

---

## vertex-ai-proxy.yml

Install vertex-ai-proxy and run it as a user-level systemd service

```bash
ansible-playbook _personal/ai-agent/vertex-ai-proxy.yml
```

**Prerequisites:**
- System-wide Node.js installed via `core/nodejs.yml`
  - version manager-managed Node.js will cause the playbook to fail

This playbook:
- Installs `vertex-ai-proxy` globally via npm
- Creates `~/.config/systemd/user/vertex-ai-proxy.service`
- Enables systemd lingering so the service survives logout
- Enables and starts the service immediately

The service listens on **port 8001** and passes `$GOOGLE_CLOUD_LOCATION` (set in `cloud-cli/env-tmpl.sh`) as the Gemini region.

**Required setup before starting the service:**

Ensure `GOOGLE_CLOUD_LOCATION` is exported in your environment (via `cloud-cli/env-tmpl.sh`), then run `vertex-ai-proxy config` once to configure the proxy (Google Cloud project, credentials, etc.):

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

## claude-code.yml

Install Claude Code CLI

```bash
ansible-playbook _personal/ai-agent/claude-code.yml
```

Installs the Claude Code CLI tool using the official installation script. The playbook:
- Installs prerequisites (curl, ca-certificates)
- Downloads and runs the official Claude Code installer
- Ensures `~/.local/bin` is added to PATH in `.bashrc`, `.profile`, and `/etc/environment`
- Respects `HTTPS_PROXY` environment variable
- Verifies installation and displays version

**Optional environment variables (set in `env-tmpl.sh`):**

- `CLAUDE_CODE_USE_VERTEX` — Use Vertex AI for Claude Code
- `ANTHROPIC_VERTEX_PROJECT_ID` — GCP project ID for Vertex AI
- `CLOUD_ML_REGION` — GCP region for Vertex AI

After installation, authenticate with:

```bash
claude auth login
```

Documentation: <https://claude.ai/code>
