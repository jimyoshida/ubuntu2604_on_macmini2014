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
| [gui-tools/](gui-tools/README.md) | GUI tools (VS Code) |
| [services/](services/README.md) | Self-hosted services (Vault, n8n, Jellyfin, Samba, FreshRSS) |

## Playbooks (multi-user)

Multi-user successors to the retired `tool/`: root-owned system paths and `/etc` drop-ins instead of
per-user Homebrew and `~/.bashrc`, so a tool installed once is usable by every account on a
**shared** workstation. Run against a remote host (`-e host=<inventory host or group>`), not
`localhost`; see [MIGRATION.md](MIGRATION.md) for the migration policy and per-playbook status.

| Directory | Description |
|-----------|-------------|
| [_multi-user/tools/](_multi-user/tools/README.md) | Developer tools (bats, gomplate, shellcheck, trivy, hadolint, grype-syft, modern-cli-tools, yq, junit2html, markdownlint, kube-score) |
| [_multi-user/cloud-cli/](_multi-user/cloud-cli/README.md) | Cloud/service CLI tools (aws-cli; migration in progress, see [MIGRATION2.md](MIGRATION2.md)) |

## Playbooks (personal)

The opposite staging tree: playbooks that are per-identity **by nature** and are not candidates
for migration, because what they install is an identity rather than a tool — an agent's
credentials, a user systemd service, a checkout in `$HOME`. The leading underscore means
staging, same convention as `_multi-user/`.

Same push model as `_multi-user/`, but with a second required var. `host` names the machine;
`target_users` names the accounts on it to provision. The account Ansible connects as is
neither of those — defaulting the work to it would reproduce the `$USER` bug this tree exists
to avoid, so the accounts are always named explicitly:

```bash
cd _personal
ansible-playbook ai-agent/claude-code.yml -e host=ws01 -e target_users=alice,bob
```

| Directory | Description |
|-----------|-------------|
| [_personal/ai-agent/](_personal/ai-agent/README.md) | AI agent tools (Claude Code, NanoClaw, vertex-ai-proxy) |

## Multi-user support status

Which playbooks install for **every** account on the box, and which install for only the one
that runs them. Classified against the [MIGRATION.md](MIGRATION.md) policy points and the
[MIGRATION2.md](MIGRATION2.md) amendments. 51 playbooks:

| Category | Count | Meaning |
|----------|-------|---------|
| [Multi-user](#multi-user-12) | 12 | Root-owned paths, `/etc` drop-ins, verified as an unprivileged uid |
| [Effectively shared](#effectively-shared-12) | 12 | Legacy, but apt/system paths only — nothing lands in a `$HOME` |
| [Mixed](#mixed--shared-install-personal-tail-14) | 14 | Shared install plus a tail that benefits only the invoker |
| [Personal only](#personal-only-13) | 13 | The whole install lands in one `$HOME` or one account |

The 36 playbooks in the legacy tree are all `hosts: localhost` with `connection: local`, so even
the "effectively shared" ones among them are personal in *execution model* — run on the box, by
one person. They are shared only in *outcome*. Both underscore trees use the push model instead,
for opposite reasons: `_multi-user/` because the install belongs to no one account, `_personal/`
because it belongs to accounts named explicitly rather than to whoever is logged in.

### Multi-user (12)

All of `_multi-user/tools/` (11) and `_multi-user/cloud-cli/aws-cli.yml`. Each uses
`hosts: "{{ host }}"`, installs to root-owned system paths, puts shell configuration in
`/etc/profile.d` or `/etc/environment`, pins its version in `vars:`, and ends with a
`setpriv --reuid=65534` task that proves the tool works for an account that is not the
connecting user.

### Effectively shared (12)

| Playbook | Why it is already safe |
|----------|------------------------|
| `cloud-cli/{azure,gcloud,github,opentofu,prometheus}-cli.yml` | Vendor apt repository plus apt package |
| `cloud-cli/aws-cli.yml` | Installs to `/usr/local/bin/aws` — but its `creates:` guard makes `--update` unreachable, which is what `_multi-user/cloud-cli/aws-cli.yml` fixes |
| `cloud-cli/gitlab-cli.yml` | Upstream `.deb` |
| `core/nodejs.yml`, `core/disable-rsyslog.yml` | apt / systemd only |
| `container/devcontainers.yml` | `npm install -g` as root |
| `gui-tools/vscode.yml` | apt (`vscode_user` is declared but never used) |
| `services/jellyfin.yml` | apt plus a system service |

### Mixed — shared install, personal tail (14)

| Playbook | Shared part | Personal part |
|----------|-------------|---------------|
| `container/{helm,kubectl,kind,minikube}.yml` | apt or `/usr/local/bin` | Bash completion written to `/home/{{ *_user }}/.bashrc` |
| `container/{docker,podman}.yml` | Daemon and packages | Only `$USER` is added to the `docker` group; `~/.bashrc` |
| `core/golang.yml` | `/usr/local/go` | `PATH` and `GOPATH` in the invoker's `.bashrc` |
| `core/mise.yml` | apt | `mise activate` in `~/.bashrc` |
| `cloud-cli/jenkins-cli.yml` | `/usr/local/lib/jenkins-cli.jar` and wrapper | The invoker's `JENKINS_URL` is baked into the shared wrapper |
| `cloud-cli/azure-devops-cli.yml` | `az` via apt | Tasks 7–9 run `become: no`, so the extension and org/project defaults land in the invoker's `~/.azure` |
| `services/vault.yml` | Vault service and `/etc/vault.d` | `VAULT_ADDR` in `~/.bashrc` |
| `services/n8n.yml` | systemd unit | `User={{ target_user }}`; `/var/lib/n8n` owned by the invoker |
| `services/freshrss.yml` | Container and network | Data directory under `/home/{{ target_user }}` |
| `services/samba.yml` | `smb.conf` and service | `smbpasswd -a` for the invoker only |

### Personal only (13)

Three of these now live in [`_personal/`](#playbooks-personal), which is where this category is
meant to end up. The rest are still mixed in with the shared trees.

| Playbook | Cause |
|----------|-------|
| `cloud-cli/{gcx,influx,jira,vault}-cli.yml` | Homebrew as `lookup('env', 'USER')` |
| `core/homebrew.yml` | The root of that cause — the tree is owned by one account |
| `_personal/ai-agent/claude-code.yml` | `install.sh` into `~/.local/bin`, plus `~/.bashrc` and `~/.profile` |
| `_personal/ai-agent/vertex-ai-proxy.yml` | `~/.config/systemd/user` unit plus `enable-linger $USER` |
| `_personal/ai-agent/nanoclaw.yml` | Repository in `/home/$USER/nanoclaw`, lingering, docker-group check |
| `container/krew.yml` | `~/.krew` prefix plus `~/.bashrc` PATH |
| `core/rust.yml` | rustup into `~/.cargo` |
| `core/ssh-key-setup.yml` | `become: no`, `~/.ssh` |
| `core/x11vnc.yml` | `/home/$USER/.vnc`, user systemd unit, `~/.bashrc` |
| `core/agent-base.yml` | `~/.xprofile`, `~/.xsessionrc`, three `~/.bashrc` blocks |

Two of these are per-identity **by nature** rather than by defect: `core/ssh-key-setup.yml` and
`core/homebrew.yml`. The fix for that shape is the one MIGRATION.md already names — an explicit
user list instead of `$USER` — not a move to `/usr/local`.

