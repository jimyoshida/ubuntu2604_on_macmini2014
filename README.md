# Ubuntu 26.04 Workstation Setup

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

## Playbooks (old)

| Directory | Description |
|-----------|-------------|
| [core/](core/README.md) | Core system setup (SSH, Samba, runtimes) |
| [container/](container/README.md) | Container runtimes and Kubernetes tools (Docker, Podman, kubectl, Helm, Krew) |
| [cloud-cli/](cloud-cli/README.md) | Cloud provider CLI tools (AWS, Azure, GCP, GitHub, GitLab) |
| [ai-agent/](ai-agent/README.md) | AI agent tools (Claude Code, Antigravity CLI, OpenClaw) |
| [tool/](tool/README.md) | Developer tools (kube-score, gomplate, modern CLI tools) |
| [gui-tools/](gui-tools/README.md) | GUI tools (VS Code) |
| [services/](services/README.md) | Self-hosted services (Vault, n8n, Jellyfin, Samba, FreshRSS) |

## Playbooks (new)

Multi-user successors to `tool/`: root-owned system paths and `/etc` drop-ins instead of
per-user Homebrew and `~/.bashrc`, so a tool installed once is usable by every account on a
**shared** workstation. Run against a remote host (`-e host=<inventory host or group>`), not
`localhost`; see [MIGRATION.md](MIGRATION.md) for the migration policy and per-playbook status.

| Directory | Description |
|-----------|-------------|
| [_multi-user/tools/](_multi-user/tools/README.md) | Developer tools (bats, gomplate, shellcheck, trivy, hadolint, grype-syft, modern-cli-tools, yq, junit2html, markdownlint, kube-score) |

