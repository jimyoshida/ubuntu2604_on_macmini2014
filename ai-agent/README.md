# AI Agent Tools

#### openclaw.yml

OpenClaw Slack agent setup

```bash
ansible-playbook ai-agent/openclaw.yml
```

**Prerequisites:**
- Run `mise.yml` first to install Node.js LTS
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
