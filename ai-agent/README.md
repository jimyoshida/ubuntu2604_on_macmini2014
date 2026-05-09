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
