# Ubuntu 26.04 Agent Workstation Setup

This directory contains Ansible playbooks for multi-user Ubuntu 26.04 agent workstation setup.

## Prerequisites

Ubuntu 24.04 or 26.04 with system packages up to date and Ansible 2.16 or 2.20 installed respectively:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ansible
```

## Passwordless Sudo Setup

Configure passwordless sudo first:

```bash
./setup-passwordless-sudo.sh
```

This eliminates the need for `-K` (or `--ask-become-pass`) flags and avoids sudo prompt compatibility issues with newer Ubuntu versions.

## Passwordless SSH Setup

After uploading `id_rsa` and `id_rsa.pub` to `~/.ssh`, and after running
[`core/agent-base.yml`](core/README.md#agent-baseyml) to configure the SSH server:

```bash
./setup-passwordless-ssh.sh
```

Sets `~/.ssh` to `0700`, the private key to `0600`, the public key to `0644` and `config` and
`authorized_keys` to `0600`, then appends your public key to `authorized_keys` unless that
exact line is already there. Missing files are reported and skipped rather than treated as an
error, so it is safe to run before the keys are in place.

This is a script rather than a playbook for the same reason
[`setup-passwordless-sudo.sh`](setup-passwordless-sudo.sh) is: it configures **the account
running it**, needs no privileges and no remote connection, and touches nothing outside that
account's `$HOME`. It was `core/ssh-key-setup.yml` until 2026-08-10 — a `become: no`,
`connection: local` playbook whose every task was a `chmod` — and the conversion cost the repo
nothing except an Ansible dependency for the one step you run before Ansible is useful.

## Playbooks (old)

What is left of the original single-user tree, which is now `core/` and nothing else. Five
directories no longer exist: `tool/` (see [MIGRATION.md](MIGRATION.md)), `cloud-cli/` (see
[MIGRATION2.md](MIGRATION2.md)) and `container/` (see [MIGRATION3.md](MIGRATION3.md))
graduated into the multi-user tree in the next table, and `services/` and `gui-tools/` were
deleted outright as out of scope — see [Retired: `services/`](#retired-services) and
[Retired: `gui-tools/`](#retired-gui-tools). `core/` has not been looked at yet, and is the
harder problem: `agent-base.yml` and `x11vnc.yml` are desktop-session and VNC setup, which is
per-identity in a way no relocation fixes.

| Directory | Description |
|-----------|-------------|
| [core/](core/README.md) | Core system setup (SSH, Samba, runtimes) |

## Playbooks (multi-user)

Multi-user successors to the retired old ones: root-owned system paths and `/etc` drop-ins instead of
per-user Homebrew and `~/.bashrc`, so a tool installed once is usable by every account on a
**shared** workstation. Run against a remote host (`-e host=<inventory host or group>`), not
`localhost`; see [MIGRATION.md](MIGRATION.md) for the migration policy and per-playbook status.

| Directory | Description |
|-----------|-------------|
| [_multi-user/tools/](_multi-user/tools/README.md) | Developer tools (bats, gomplate, shellcheck, trivy, hadolint, grype-syft, modern-cli-tools, yq, junit2html, markdownlint, kube-score) |
| [_multi-user/cloud-cli/](_multi-user/cloud-cli/README.md) | Cloud/service CLI tools (aws, az, az devops, gcloud, gcx, gh, glab, influx, jenkins, jira, tofu, promtool/amtool, vault — the [MIGRATION2.md](MIGRATION2.md) migration is complete) |
| [_multi-user/container/](_multi-user/container/README.md) | Container runtimes and Kubernetes tools (Docker, Podman, kubectl, Helm, kind, minikube, devcontainers — the [MIGRATION3.md](MIGRATION3.md) migration is complete) |

One difference to know before running `container/docker.yml`, because it reads as a regression
and is not one: it grants **no** account access to the Docker socket unless you name them in
`docker_users`, where its predecessor added whoever ran it automatically. Membership of that
group is equivalent to passwordless root, so it is typed out per account, per run — see
[Grants](_multi-user/container/README.md#grants). `podman_linger_users` works the same way.

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

## Retired: `services/`

This repo provisions a **workstation**, not an application server, so the directory that
deployed long-running self-hosted servers is gone (2026-08-10). Nothing replaced it — these
playbooks were deleted rather than migrated — except `samba.yml`, which moved into `core/`.

| Playbook | Fate |
|----------|------|
| `services/vault.yml` | Deleted first, with the local Vault server it had deployed. The client half is [`_multi-user/cloud-cli/vault-cli.yml`](_multi-user/cloud-cli/README.md#vault-cliyml) |
| `services/n8n.yml`, `services/jellyfin.yml`, `services/freshrss.yml` | Deleted — a workflow engine, a media server and a feed reader are services to point a workstation at, not to run on it |
| `services/samba.yml` | **Kept**, moved to [`core/samba.yml`](core/README.md#sambayml). Sharing your own home directory over SMB is a workstation function; its two variables moved into [`core/env-tmpl.sh`](core/env-tmpl.sh) |

Everything above is recoverable from git history (`git log --diff-filter=D -- services/`),
including the retired `services/README.md` — which is where the account of what the Vault
server was and how it was dismantled now lives.

## Retired: `core/homebrew.yml`

Homebrew is single-account by construction — `/home/linuxbrew/.linuxbrew` is owned by whoever
installed it, and upstream refuses `sudo brew` — so on a shared workstation it could never be
anything but a personal install. It was the last structural cause of that shape here, and it
ran out of dependents: [MIGRATION.md](MIGRATION.md) moved seven `tool/` playbooks off `brew`,
and wave 3 of [MIGRATION2.md](MIGRATION2.md) moved the remaining four
(`cloud-cli/{gcx,influx,jira,vault}-cli.yml`) to root-owned paths. Nothing in the repo installs
through `brew` any more, so the installer went too (2026-08-10).

Nothing replaces it. The two tools its section suggested installing by hand afterwards — K9s
and KDash — have no playbook here and never did.

Deleting the playbook does **not** touch a `/home/linuxbrew` tree that already exists on a host,
which is deliberate: uninstalling the leftover formulae stays a per-host cleanup, and the `PATH`
precedence follow-up in [MIGRATION2.md](MIGRATION2.md#known-follow-ups) still applies to any
account whose `~/.bashrc` runs `brew shellenv`. That cleanup was carried out by hand on
`localhost` on 2026-08-11 — see the follow-up entry — so the tree is gone there; the follow-up
stands for every other host provisioned before the retirement. The playbook is recoverable from
git history (`git log --diff-filter=D -- core/homebrew.yml`).

## Retired: `core/golang.yml` and `core/rust.yml`

Two language toolchains, installed on every workstation this repo provisions, for work that
does not happen on them. What the AI agents here actually build is Ansible, shell, Node and
Python; nothing in this repo compiles Go or Rust, and no agent has asked for either. So both
playbooks went (2026-08-10) — retired for **scope**, not for defect. Neither was broken:
`golang.yml` pinned its version explicitly and handled upgrades, and `rust.yml` deferred to
rustup, which is the correct way to install Rust. They were simply a version pin to keep
current, a `~/.bashrc` block to own and a tarball to fetch on behalf of nobody.

What replaces them, if a runtime is genuinely needed, is [`core/mise.yml`](core/README.md#miseyml)
— already in `core/`, already the polyglot answer, and per-account on demand
(`mise use --global go@1.23`) rather than a system-wide install nobody asked for. For Rust
specifically the upstream one-liner the retired playbook wrapped is still the recommended
path: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`.

The two were in different categories, so both counts above move: `golang.yml` was *mixed* — a
shared `/usr/local/go` with `PATH` and `GOPATH` in the invoker's `.bashrc` — and `rust.yml` was
*personal only*, rustup into `~/.cargo` for one account and no one else.

As with the other retirements, deleting a playbook uninstalls nothing. A host already
provisioned keeps its `/usr/local/go`, its `~/.cargo` and the `ANSIBLE MANAGED BLOCK: golang`
and `ANSIBLE MANAGED BLOCK: rust` blocks in `~/.bashrc`; removing those is a per-host cleanup
this repo no longer performs. Done by hand on `localhost` on 2026-08-11: both toolchains, the
`~/go` `GOPATH` and `~/.rustup` removed, and both `~/.bashrc` blocks dropped. One detail worth
knowing before doing it elsewhere — `rustup self uninstall` also removes the
`. "$HOME/.cargo/env"` line it wrote into `~/.profile`, which is unguarded and would otherwise
error on every login shell once `~/.cargo` is gone. Both playbooks are recoverable from git
history (`git log --diff-filter=D -- core/golang.yml core/rust.yml`).

## Retired: `container/krew.yml`

Krew is kubectl's plugin manager, and it is per-user by **design** rather than by defect:
`KREW_ROOT` defaults to `~/.krew`, and `kubectl krew install` writes into `$KREW_ROOT/store`
with `$KREW_ROOT/bin` on `PATH`. That is exactly the shape this repo has spent two migrations
removing, so it was retired (2026-08-14) instead of being carried into `_multi-user/container/`
— the one playbook of the eight in [MIGRATION3.md](MIGRATION3.md)'s scope that is dropped rather
than migrated.

A shared root is possible and is documented upstream (`KREW_ROOT=/usr/local/krew`), and it was
rehearsed here on 2026-08-11 against krew v0.5.0 with a read-only root standing in for a
root-owned tree. It works exactly as far as reading goes and no further:

| Action against a root the account cannot write | Result |
|-----------------------------------------------|--------|
| running an installed plugin (`kubectl ctx`, `kubectl ns`) | works — plain `PATH` discovery, krew is not involved |
| `kubectl krew list`, `search`, `version` | works — reads `receipts`, the local index, and prints the resolved `BasePath` |
| `kubectl krew install <plugin>` | **fails** — the index `git fetch` hits `Permission denied` |

So a shared krew gives every account the plugins root chose and gives no account a way to add
one — the Homebrew problem again, with a smaller blast radius. The alternative is worse in the
other direction: a per-account krew installed by a playbook means every account's plugin set is
managed by a run of that playbook.

Nothing replaces it, because nothing needs to. kubectl discovers plugins as `kubectl-*`
executables on `PATH`, with no manager involved, so the three plugins the old README told users
to install (`ctx`, `ns`, `node-shell`) can be plain binaries in `/usr/local/bin` named
`kubectl-ctx`, `kubectl-ns` and `kubectl-node_shell` — installable once, usable by everyone. What
is forfeited is `krew search` and `krew upgrade`. An account that wants krew for itself can run
[krew's own installer](https://krew.sigs.k8s.io/docs/user-guide/setup/install/); the retirement
does not stand in its way.

As with every other retirement here, deleting the playbook uninstalls nothing: an account that
ran it keeps its `~/.krew` tree, its installed plugins and the
`ANSIBLE MANAGED BLOCK: krew` in `~/.bashrc`, and krew goes on working there. `localhost` has
one such tree with all three plugins. Removing it is a per-host, per-account cleanup this repo
no longer performs — see
[MIGRATION3.md's follow-ups](MIGRATION3.md#known-follow-ups). The playbook is recoverable from
git history (`git log --diff-filter=D -- container/krew.yml`) — as is the rest of `container/`,
which went the same day once its seven other playbooks had verified successors in
[`_multi-user/container/`](_multi-user/container/README.md).

## Retired: `gui-tools/`

The directory held one playbook, `vscode.yml`, and it is gone with the directory (2026-08-14).
Retired for **scope**, like `services/` and the two language toolchains, not for defect: it was
an ordinary apt install from `packages.microsoft.com/repos/code`, guarded on `dpkg -l code`, and
its only blemish was a `vscode_user` variable that was declared and never used.

What it installed was a GUI editor, on a box whose work arrives over SSH. This host is the
argument: `code` has never been installed here as a package, there is no
`/etc/apt/sources.list.d/vscode.list` and no `/usr/share/keyrings/packages.microsoft.gpg` — the
only `code` on it is the Remote-SSH server VS Code unpacked into `~/.vscode-server` by itself,
for one account, when someone connected from their own machine. That is where the editor
belongs: on the client. A workstation that runs AI coding agents needs the toolchains the agents
call, not a desktop application nobody launches locally.

Nothing replaces it. Anyone who does want VS Code on the box installs it the way the playbook
did — `sudo apt install code` where the repository is already configured, or upstream's
[Linux install page](https://code.visualstudio.com/docs/setup/linux) where it is not. Neither
needs Ansible, and neither is worth a playbook to wrap.

The extension list the playbook printed at the end (`ms-python.python`, `redhat.ansible`,
`hashicorp.terraform` and two for the [retired
toolchains](#retired-coregolangyml-and-corerustyml)) was advice, not configuration, and it goes
with the playbook.

As with the other retirements, deleting it uninstalls nothing: a host that ran it keeps the
`code` package, the `vscode.list` apt source and the Microsoft keyring, and keeps getting VS
Code updates through `apt upgrade`. Removing those is a per-host cleanup this repo no longer
performs. Note that the repository is *not* the one
[`_multi-user/cloud-cli/azure-cli.yml`](_multi-user/cloud-cli/README.md#azure-cliyml) manages
(`/repos/azure-cli`, under its own keyring and `.sources` file), so retiring this playbook
neither breaks nor cleans up that one. The playbook and its README are recoverable from git
history (`git log --diff-filter=D -- gui-tools/`).

## Multi-user support status

Which playbooks install for **every** account on the box, and which install for only the one
that runs them. Classified against the [MIGRATION.md](MIGRATION.md) policy points and the
[MIGRATION2.md](MIGRATION2.md) and [MIGRATION3.md](MIGRATION3.md) amendments. 40 playbooks:

| Category | Count | Meaning |
|----------|-------|---------|
| [Multi-user](#multi-user-31) | 31 | Root-owned paths, `/etc` drop-ins, verified as an unprivileged uid |
| [Effectively shared](#effectively-shared-2) | 2 | Legacy, but apt/system paths only — nothing lands in a `$HOME` |
| [Mixed](#mixed--shared-install-personal-tail-2) | 2 | Shared install plus a tail that benefits only the invoker |
| [Personal only](#personal-only-5) | 5 | The whole install lands in one `$HOME` or one account |

Three quarters of the repo is now multi-user, and the balance moved in one step rather than
gradually: a migrated playbook is a *new* file, so during a migration both generations are
counted, and the total drops back when the originals are retired. That has now happened
three times, and all three migrations are finished: `tool/` after MIGRATION.md, all thirteen
of `cloud-cli/` after MIGRATION2.md, and all seven of `container/` after MIGRATION3.md. None
of the three directories still exists. The total is unchanged at 40 across the last of them
because seven successors replaced exactly seven originals. Nine playbooks went the other
way and were deleted rather than migrated: all of `services/` except `samba.yml`, which moved
to `core/` (see [Retired: `services/`](#retired-services)); `core/homebrew.yml`, which was
deleted once the migrations left it with no dependents (see
[Retired: `core/homebrew.yml`](#retired-corehomebrewyml)); `core/golang.yml` and
`core/rust.yml`, which were out of scope for a workstation that runs AI coding agents (see
[Retired: `core/golang.yml` and `core/rust.yml`](#retired-coregolangyml-and-corerustyml));
`container/krew.yml`, the first casualty of [MIGRATION3.md](MIGRATION3.md), dropped because a
plugin manager with a shared root can be read by every account and written by none (see
[Retired: `container/krew.yml`](#retired-containerkrewyml)); and `gui-tools/vscode.yml`, a GUI
editor on a box whose work arrives over SSH, which took its directory with it (see
[Retired: `gui-tools/`](#retired-gui-tools)).

The 6 playbooks left in the legacy tree — all of `core/`, which is all the legacy tree is now —
are `hosts: localhost` with `connection: local`, so even
the "effectively shared" ones among them are personal in *execution model* — run on the box, by
one person. They are shared only in *outcome*. Both underscore trees use the push model instead,
for opposite reasons: `_multi-user/` because the install belongs to no one account, `_personal/`
because it belongs to accounts named explicitly rather than to whoever is logged in.

### Multi-user (31)

All of `_multi-user/tools/` (11), all of `_multi-user/cloud-cli/` (13) and all of
`_multi-user/container/` (7). Each uses
`hosts: "{{ host }}"`, installs to root-owned system paths, puts shell configuration in
`/etc/profile.d`, `/etc/bash_completion.d` or `/etc/environment`, pins its version in
`vars:`, and ends with a `setpriv --reuid=65534` task that proves the tool works for an
account that is not the connecting user.

The `_multi-user/cloud-cli/` ones add a rule the `tools/` ones did not need: every tool there carries an
identity, so the playbook installs the client and stops. None of them runs `aws configure`,
`gcloud auth login` or `jira init`, and none writes a secret anywhere.

The `_multi-user/container/` ones add three more, because what they install is a *runtime*
rather than a client: a privilege grant takes an explicit list and defaults to empty (see the
note under [Playbooks (multi-user)](#playbooks-multi-user)); no playbook creates or
pre-populates per-account runtime state — `~/.kube`, `~/.minikube`, `~/.docker` — for any
account, including the connecting one; and the closing check proves an unprivileged account
can run the client, not that a cluster exists. One consequence is worth stating rather than
discovering: `kind` and `minikube` are multi-user exactly as far as the `docker` group
reaches. Every account can execute the binary, and no account outside `docker_users` can do
anything with it.

### Effectively shared (2)

This category used to be mostly `cloud-cli/`; those seven playbooks were migrated and their
originals deleted, `services/jellyfin.yml` left with the rest of `services/`,
`gui-tools/vscode.yml` left with [its directory](#retired-gui-tools), and
`container/devcontainers.yml` — the third row here until 2026-08-14 — was migrated to
[`_multi-user/container/devcontainers.yml`](_multi-user/container/README.md#devcontainersyml)
and deleted with the rest of `container/`. What is left is the tail.

| Playbook | Why it is already safe |
|----------|------------------------|
| `core/nodejs.yml`, `core/disable-rsyslog.yml` | apt / systemd only |

### Mixed — shared install, personal tail (2)

This category was three quarters `container/` until 2026-08-14: `docker`, `podman`, `kubectl`,
`helm`, `kind` and `minikube` were six of its eight rows, each a shared install with a
`~/.bashrc` block or a `$USER` group add on the end, and all six left the category by being
[migrated](MIGRATION3.md) — the completions moved to `/etc/bash_completion.d` and the group
add became `docker_users`. `core/golang.yml` was a ninth row before that, and left the other
way: [retired](#retired-coregolangyml-and-corerustyml) rather than fixed, since a toolchain
nobody here compiles with is not worth un-mixing. What is left is `core/` alone.

| Playbook | Shared part | Personal part |
|----------|-------------|---------------|
| `core/mise.yml` | apt | `mise activate` in `~/.bashrc` |
| `core/samba.yml` | `smb.conf` and service | `smbpasswd -a` for the invoker only |

### Personal only (5)

Three of these now live in [`_personal/`](#playbooks-personal), which is where this category is
meant to end up. The other two are still mixed in with the shared trees. Four more left the
category without being fixed: `core/homebrew.yml` was [retired](#retired-corehomebrewyml) — it
had been the root cause of four other entries here, `cloud-cli/{gcx,influx,jira,vault}-cli.yml`,
all `brew install` as `lookup('env', 'USER')`, until wave 3 of MIGRATION2.md moved those to
root-owned paths — `core/rust.yml` was
[retired with `core/golang.yml`](#retired-coregolangyml-and-corerustyml) as out of scope,
`container/krew.yml` was [retired](#retired-containerkrewyml) as per-user by design rather than
by defect, and `core/ssh-key-setup.yml` became
[`setup-passwordless-ssh.sh`](#passwordless-ssh-setup), since a playbook whose every task was a
`chmod` inside the invoker's own `~/.ssh` was never getting anything from Ansible.

| Playbook | Cause |
|----------|-------|
| `_personal/ai-agent/claude-code.yml` | `install.sh` into `~/.local/bin`, plus `~/.bashrc` and `~/.profile` |
| `_personal/ai-agent/vertex-ai-proxy.yml` | `~/.config/systemd/user` unit plus `enable-linger $USER` |
| `_personal/ai-agent/nanoclaw.yml` | Repository in `/home/$USER/nanoclaw`, lingering, docker-group check |
| `core/x11vnc.yml` | `/home/$USER/.vnc`, user systemd unit, `~/.bashrc` |
| `core/agent-base.yml` | `~/.xprofile`, `~/.xsessionrc`, three `~/.bashrc` blocks |

The two still in the shared trees are per-identity by **defect** — each binds its work to
whoever happens to run it. The fix for that shape is the one MIGRATION.md already names: an
explicit user list instead of `$USER`, not a move to `/usr/local`. The three in `_personal/`
are per-identity **by nature** and need no fix.

