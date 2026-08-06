# ubuntu2604_on_macmini2014

This directory contains Ansible playbooks for automated Ubuntu 26.04 agent environment setup.

## Prerequisites

Ubuntu 26.04 with system packages up to date and Ansible 2.20 installed:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ansible
```

## Passwordless Sudo Setup

For a smoother experience, especially on Ubuntu 26.04+, configure passwordless sudo first:

```bash
./setup-passwordless-sudo.sh
```

This eliminates the need for `-K` (or `--ask-become-pass`) flags and avoids sudo prompt compatibility issues with newer Ubuntu versions.

## Playbooks

| Directory | Description |
|-----------|-------------|
| [core/](core/README.md) | Core system setup (SSH, Samba, runtimes) |
| [container/](container/README.md) | Container runtimes and Kubernetes tools (Docker, Podman, kubectl, Helm, Krew) |
| [cloud-cli/](cloud-cli/README.md) | Cloud provider CLI tools (AWS, Azure, GCP, GitHub, GitLab) |
| [ai-agent/](ai-agent/README.md) | AI agent tools (Claude Code, Antigravity CLI, OpenClaw) |
| [tool/](tool/README.md) | Developer tools (kube-score, gomplate, modern CLI tools) |
| [gui-tools/](gui-tools/README.md) | GUI tools (VS Code) |
| [services/](services/README.md) | Self-hosted services (Vault, n8n) |
| [media/](media/README.md) | Media tools (Jellyfin, Samba, FreshRSS) |

## Ongoing Migrations

- **Multi-User Workstation Tool Playbook Migration** — [MIGRATION.md](MIGRATION.md)
  - Policy and procedure for moving the tool installation playbooks from
    `tool/` (single-user) to `_multi-user/tools/` (multi-user)
  - Current status of each playbook
