# AI Agent Tools

## nanoclaw.yml

NanoClaw agent setup (Docker-based, lightweight OpenClaw alternative)

```bash
cd _personal
ansible-playbook ai-agent/nanoclaw.yml -e host=ws01 -e target_users=alice
```

**Prerequisites:**
- Docker installed on the target host —
  [`_multi-user/container/docker.yml`](../../_multi-user/container/README.md#dockeryml)
- **Every account in `target_users`** in the `docker` group — checked per account, not for the
  connecting user, since that playbook grants the group only to the accounts named in
  `docker_users` and grants none by default:
  ```bash
  cd _multi-user
  ansible-playbook container/docker.yml -e host=ws01 -e docker_users=alice
  ```
  The group is equivalent to passwordless root on the host, which is why it is typed out per
  account rather than inferred; `usermod -aG docker <account>` does the same thing by hand.
  `nanoclaw.yml` itself fails with a clear message naming the account if Docker is missing or
  any target account is not in the group.

This playbook:
- Installs `build-essential`, `python3`, `curl`, `git` via apt
- Clones `https://github.com/nanocoai/nanoclaw.git` to each account's `~/nanoclaw`, as that account
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
cd _personal
ansible-playbook ai-agent/vertex-ai-proxy.yml -e host=ws01 -e target_users=alice \
  -e google_cloud_location=asia-northeast1
```

**Prerequisites:**
- System-wide Node.js installed via `_multi-user/core/nodejs.yml`
  - version manager-managed Node.js will cause the playbook to fail

This playbook:
- Installs `vertex-ai-proxy` globally via npm, once, as root — the package is shared
- Creates `~/.config/systemd/user/vertex-ai-proxy.service` for each account in `target_users`
- Enables systemd lingering so the service survives logout
- Enables and starts the service immediately, and fails the run if it does not come up active

The service listens on **port 8001** and takes its Gemini region from the required
`google_cloud_location` var, written into the unit as an `Environment=` line.

This is deliberately *not* read from a shell profile. A systemd user unit does not source the
account's shell, so the `${GOOGLE_CLOUD_LOCATION}` the pre-migration playbook interpolated
into `ExecStart` expanded to an empty string at service start regardless of what was exported
— including from `cloud-cli/env-tmpl.sh`, the shared template that used to carry that
variable and has since been deleted. Pass it on the command line instead:

```bash
-e google_cloud_location=asia-northeast1
```

**Required setup before the proxy is usable:**

Installation needs no credentials, but each account supplies its own before the proxy can serve
it. On the target host, as that account:

```bash
vertex-ai-proxy config              # Google Cloud project, credentials
gcloud auth application-default login
```

**Managing the service** (as the account that owns it):
```bash
systemctl --user status vertex-ai-proxy   # Check status
systemctl --user restart vertex-ai-proxy  # Restart
journalctl --user -u vertex-ai-proxy -f   # View logs
systemctl --user stop vertex-ai-proxy     # Stop
```

## claude-code.yml

Install Claude Code CLI

```bash
cd _personal
ansible-playbook ai-agent/claude-code.yml -e host=ws01 -e target_users=alice
```

Installs the Claude Code CLI tool using the official installation script, once per account in
`target_users`. The playbook:
- Installs prerequisites (curl, ca-certificates)
- Runs the official installer **as each account**, so the CLI lands in that account's `~/.local/bin`
- Ensures `~/.local/bin` is on PATH via that account's `.bashrc` and `.profile`
- Verifies the CLI runs **as each provisioned account**, and fails the run if it does not

**Optional vars** (pass with `-e`):

| Var | Default | Purpose |
|-----|---------|---------|
| `https_proxy_url` | `''` | Proxy for the installer download |

Note this is a play var, not an environment variable read from the operator's shell: in a push
model an env lookup evaluates on the control node, not on the target.

After installation, each account authenticates itself on the target host:

```bash
claude auth login
```

Documentation: <https://claude.ai/code>
