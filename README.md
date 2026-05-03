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
| [core/](core/README.md) | Core system setup (SSH, Samba, Docker, Podman, runtimes) |
| [cloud-cli/](cloud-cli/README.md) | Cloud provider CLI tools (AWS, Azure, GCP, GitHub, GitLab) |
| [k8s/](k8s/README.md) | Kubernetes tools (kubectl, Helm, Krew) |
| [o11y/](o11y/README.md) | Observability tools (Grafana, Loki, Tempo, Mimir) |
| [ai-agent/](ai-agent/README.md) | AI agent tools (Claude Code, OpenClaw) |
