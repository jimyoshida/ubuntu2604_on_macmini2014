# Ubuntu 26.04 Agent Workstation Setup

This directory contains Ansible playbooks for multi-user Ubuntu 26.04 agent workstation setup.

## Prerequisites

Ubuntu 24.04 or 26.04 with system packages up to date and Ansible 2.16 or 2.20 installed respectively:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ansible
```

## Passwordless sudo and SSH

Both are host-bootstrap steps rather than part of running these playbooks, and are documented
in [Desktop Host Setup](DESKTOP-HOST-SETUP.md): [Passwordless sudo](DESKTOP-HOST-SETUP.md#passwordless-sudo)
and [Passwordless SSH](DESKTOP-HOST-SETUP.md#passwordless-ssh). Run both first if the remote host
doesn't have them yet — an AWS EC2 instance (or similar cloud image) usually already does: the
AMI grants the default user passwordless sudo and cloud-init injects your key into
`authorized_keys` at launch.

## Playbooks

Root-owned system paths and `/etc` drop-ins, not per-user Homebrew or `~/.bashrc`, so a tool
installed once is usable by every account on a **shared** workstation. Run against a remote host
(`-e host=<inventory host or group>`), not `localhost`.

| Directory | Description |
|-----------|-------------|
| [_multi-user/tools/](_multi-user/tools/README.md) | Developer tools (bats, gomplate, shellcheck, trivy, hadolint, grype-syft, jq, jsonnet, yq, junit2html, markdownlint, kube-score) |
| [_multi-user/cloud-cli/](_multi-user/cloud-cli/README.md) | Cloud/service CLI tools (aws, az, az devops, gcloud, gcx, gh, glab, influx, jenkins, jira, tofu, promtool/amtool, vault) |
| [_multi-user/container/](_multi-user/container/README.md) | Container runtimes and Kubernetes tools (Docker, Podman, kubectl, Helm, kind, minikube, devcontainers) |
| [_multi-user/core/](_multi-user/core/README.md) | Core CLI tools, modern CLI tool replacements, Node.js/Yarn/pnpm, mise |

One thing to know before running `container/docker.yml`: it grants **no** account access to the
Docker socket unless you name them in `docker_users` — membership of that group is equivalent to
passwordless root, so it's typed out per account, per run. See
[Grants](_multi-user/container/README.md#grants). `podman_linger_users` works the same way.

## History

This repo was migrated from an earlier single-user layout to the multi-user one above across
four migrations; see [MIGRATION.md](MIGRATION.md), [MIGRATION2.md](MIGRATION2.md),
[MIGRATION3.md](MIGRATION3.md) and [MIGRATION4.md](MIGRATION4.md) for that history, and `git log`
for anything deleted along the way.
