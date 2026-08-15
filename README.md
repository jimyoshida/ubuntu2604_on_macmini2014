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

After uploading `id_rsa` and `id_rsa.pub` to `~/.ssh` (sshd itself is assumed already enabled on
the host):

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

Nothing is left of the original single-user tree. All four directories that once lived here
graduated into the multi-user tree below — `tool/` (see [MIGRATION.md](MIGRATION.md)),
`cloud-cli/` (see [MIGRATION2.md](MIGRATION2.md)), `container/` (see
[MIGRATION3.md](MIGRATION3.md)) and, last, `core/` (see [MIGRATION4.md](MIGRATION4.md)) —
while `services/` and `gui-tools/` were deleted outright as out of scope instead — see
[Retired: `services/`](#retired-services) and [Retired: `gui-tools/`](#retired-gui-tools).
`core/` looked like the harder problem — `agent-base.yml` mixed desktop-session setup into
hostname, network and package tasks, which read as per-identity in a way no relocation could
fix — but the desktop half turned out to be separable rather than structural. `x11vnc.yml` and
`disable-rsyslog.yml` were retired outright (see
[Retired: `core/disable-rsyslog.yml` and `core/x11vnc.yml`](#retired-coredisable-rsyslogyml-and-corex11vncyml)),
`samba.yml` followed the same way (see [Retired: `core/samba.yml`](#retired-coresambayml)), and
`agent-base.yml` itself lost its SSH, Avahi, logind, journald, hostname and IPv6 tasks one at a
time until only package installation was left — renamed `core/core-tools.yml` (2026-08-14). What
remained — `core-tools.yml`, `nodejs.yml` and `mise.yml` — was straightforwardly multi-user
compatible and migrated to [`_multi-user/core/`](_multi-user/core/README.md) per
[MIGRATION4.md](MIGRATION4.md); the three originals and `core/README.md` were deleted on
2026-08-16 once every successor was verified, the same gate `tool/`, `cloud-cli/` and
`container/` passed before it. `_personal/` went the same day, but by the `services/`/
`gui-tools/` route rather than this one — deleted outright, with no successor — because what it
held was out of scope for a different reason: not a desktop or a hosted service, but per-identity
work that belongs to the account it's for, not to a shared workstation-provisioning repo. See
[Retired: `_personal/`](#retired-_personal). Nothing named `core/`, `tool/`, `cloud-cli/`,
`container/`, `services/`, `gui-tools/` or `_personal/` remains anywhere in the repo — only
[`_multi-user/`](#playbooks-multi-user) below. Every deleted playbook is recoverable from git
history (`git log --diff-filter=D -- core/` for the last of the migrated ones, `git log
--diff-filter=D -- _personal/` for the retired-outright ones).

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
| [_multi-user/core/](_multi-user/core/README.md) | Core CLI tools, Node.js/Yarn/pnpm, mise (the [MIGRATION4.md](MIGRATION4.md) migration is complete) |

One difference to know before running `container/docker.yml`, because it reads as a regression
and is not one: it grants **no** account access to the Docker socket unless you name them in
`docker_users`, where its predecessor added whoever ran it automatically. Membership of that
group is equivalent to passwordless root, so it is typed out per account, per run — see
[Grants](_multi-user/container/README.md#grants). `podman_linger_users` works the same way.

## Retired: `services/`

This repo provisions a **workstation**, not an application server, so the directory that
deployed long-running self-hosted servers is gone (2026-08-10). Nothing replaced it — these
playbooks were deleted rather than migrated — except `samba.yml`, which moved into `core/` at
the time and outlived the rest of the directory by four days. It was retired from there too on
2026-08-14, once the exception stopped holding up — see
[Retired: `core/samba.yml`](#retired-coresambayml).

| Playbook | Fate |
|----------|------|
| `services/vault.yml` | Deleted first, with the local Vault server it had deployed. The client half is [`_multi-user/cloud-cli/vault-cli.yml`](_multi-user/cloud-cli/README.md#vault-cliyml) |
| `services/n8n.yml`, `services/jellyfin.yml`, `services/freshrss.yml` | Deleted — a workflow engine, a media server and a feed reader are services to point a workstation at, not to run on it |
| `services/samba.yml` | Moved to `core/samba.yml` on 2026-08-10, then retired from there too on 2026-08-14 — see [Retired: `core/samba.yml`](#retired-coresambayml) |

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

What replaces them, if a runtime is genuinely needed, is
[`_multi-user/core/mise.yml`](_multi-user/core/README.md#miseyml) — the polyglot answer, and
per-account on demand (`mise use --global go@1.23`) rather than a system-wide install nobody
asked for. It lived at `core/mise.yml` when this section was written; it migrated to
`_multi-user/core/` per [MIGRATION4.md](MIGRATION4.md) and `core/` itself is now retired — see
[Playbooks (old)](#playbooks-old). For Rust
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

Nothing replaces krew itself, because nothing needs to. kubectl discovers plugins as `kubectl-*`
executables on `PATH`, with no manager involved, so the three plugins the old README told users
to install (`ctx`, `ns`, `node-shell`) could always come back as plain binaries in
`/usr/local/bin`, installable once and usable by everyone. Two of them have:
[`_multi-user/container/kubectl.yml`](_multi-user/container/README.md#kubectlyml) now installs
`kubectx` and `kubens` from the Ubuntu archive's `kubectx` package — a single source with no
vendor collision to pin against, so no repository or key was needed the way kubectl's own
install requires. They land as `/usr/bin/kubectx` and `/usr/bin/kubens`, not
`kubectl-ctx` / `kubectl-ns`, so they run as direct commands rather than through kubectl's
plugin discovery — `kubectl ctx` still does not work. `node-shell` has no equivalent archive
package and remains unmigrated. What is forfeited either way is `krew search` and `krew
upgrade`. An account that wants krew for itself can run
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

## Retired: `core/disable-rsyslog.yml` and `core/x11vnc.yml`

Two more `core/` playbooks gone (2026-08-14), both for **scope**, like `gui-tools/` before them:
neither does anything an AI coding agent working over SSH needs.

`x11vnc.yml` provisioned a full virtual desktop — Xvfb, XFCE, x11vnc, GDM disabled in favor of
`multi-user.target` — to expose a GUI session nobody drives. That is the same argument that
retired [`gui-tools/vscode.yml`](#retired-gui-tools): this host's work arrives over SSH, so a
VNC-reachable desktop is infrastructure for a use case the workstation doesn't have.

`disable-rsyslog.yml` started life in the now-gone `o11y/` tree, stopping `rsyslog` from
duplicating journal entries that Alloy was already shipping to Loki — a real duplication problem.
Once `o11y/` was retired, its job narrowed to trimming rsyslog's own disk usage, a hygiene task
with no pipeline left to justify it. That's out of scope for the same reason the language
toolchains were: it's upkeep for something this workstation doesn't run, not a defect in the
playbook itself (see
[Retired: `core/golang.yml` and `core/rust.yml`](#retired-coregolangyml-and-corerustyml)).

As with every other retirement here, deleting the playbooks uninstalls nothing: a host already
provisioned by `x11vnc.yml` keeps its Xvfb/x11vnc systemd user service, `~/.vnc`, and
`multi-user.target` default, and one already provisioned by `disable-rsyslog.yml` keeps
`rsyslog.service` stopped and `syslog.socket` masked. Undoing either is the per-host cleanup
described in their respective sections while they existed. Both playbooks are recoverable from
git history (`git log --diff-filter=D -- core/disable-rsyslog.yml core/x11vnc.yml`).

## Retired: `core/samba.yml`

The last `core/` playbook to go on 2026-08-14, for the reason its two neighbors above went:
sharing your home directory over SMB is a service, and the exception that kept it around when
[`services/` was retired](#retired-services) — "a workstation function, not a hosted service" —
didn't survive a second look. It is the same shape as `services/n8n.yml`, `services/jellyfin.yml`
and `services/freshrss.yml`: something to point a workstation at, not something to run on one.

`vault.yml`'s split already established the pattern this repo prefers for anything with a
client/server shape: keep the client, drop the server. Samba has no such split to fall back on
here — the playbook's whole job was `smbd`/`nmbd` and a `[homes]` share — so there is nothing
downstream of `core/samba.yml` left to point at, unlike
[`_multi-user/cloud-cli/vault-cli.yml`](_multi-user/cloud-cli/README.md#vault-cliyml) for Vault.

Deleting it uninstalls nothing: a host already provisioned keeps `smbd` and `nmbd` running, the
`[homes]` share in `smb.conf`, and the Samba password set for whoever ran `smbpasswd -a`. Undoing
that is a per-host cleanup this repo no longer performs. The playbook, its `core/env-tmpl.sh`
entries (`SAMBA_PASSWORD`, `SAMBA_INTERFACES`) and its README section are recoverable from git
history (`git log --diff-filter=D -- core/samba.yml`), as is the original
`git log --diff-filter=D -- services/samba.yml` move from 2026-08-10.

## Retired: `_personal/`

Gone entirely (2026-08-16) — three playbooks, its `ai-agent/README.md`, and its own
`ansible.cfg`/`inventory.ini(.example)`. Unlike every retirement above it, this was not legacy
debt or an unmaintained corner: `_personal/` was a deliberate second staging tree, built up
alongside `_multi-user/` across [MIGRATION3.md](MIGRATION3.md) and
[MIGRATION4.md](MIGRATION4.md) as the place per-identity playbooks were *meant* to end up — its
`target_users` convention is even what `docker_users` and `podman_linger_users` were written to
match (see [B1 in MIGRATION3.md](MIGRATION3.md#policy-amendments)). It is retired anyway, for
**scope**, the same call as [`services/`](#retired-services) and [`gui-tools/`](#retired-gui-tools)
rather than a defect in any of the three playbooks: this repo provisions shared, multi-user
infrastructure, and an individual account's AI agent — its credentials, its checkout, its
systemd user service — is that account's own setup, not something a shared
workstation-provisioning repo should own. `_multi-user/` earns its scope because a tool
installed once serves every account; nothing in `_personal/` was ever going to do that by
nature, so keeping a permanent home for it here just because it had gained good conventions was
optimizing the wrong thing.

| Playbook | Installed |
|----------|-----------|
| `_personal/ai-agent/claude-code.yml` | Claude Code CLI via the official installer, into each named account's `~/.local/bin` |
| `_personal/ai-agent/vertex-ai-proxy.yml` | `vertex-ai-proxy`, globally via npm, plus a `~/.config/systemd/user` unit per named account |
| `_personal/ai-agent/nanoclaw.yml` | A NanoClaw checkout in `/home/$USER/nanoclaw`, systemd lingering, a `docker` group check |

Nothing replaces any of them here. An account that wants Claude Code, NanoClaw or
vertex-ai-proxy installs it the way `gui-tools/vscode.yml`'s retirement left VS Code to be
installed — by hand, or from its own dotfiles, following each tool's own upstream instructions —
which is where per-identity setup belongs once it stops being this repo's job to wrap it in a
playbook.

As with every other retirement, deleting the playbooks uninstalls nothing: an account already
provisioned by them keeps its `~/.local/bin/claude`, its `~/nanoclaw` checkout and lingering
systemd user session, and its `vertex-ai-proxy.service`, and all three keep running exactly as
before. Undoing that is a per-account cleanup this repo no longer performs. Everything —
the three playbooks, `ai-agent/README.md`, `ansible.cfg` and `inventory.ini.example` — is
recoverable from git history (`git log --diff-filter=D -- _personal/`); `inventory.ini` itself
was gitignored and held only the same RFC 5737 placeholder addresses `_multi-user/inventory.ini`
does, so nothing real was lost with it.

## Multi-user support status

Which playbooks install for **every** account on the box, and which install for only the one
that runs them. Classified against the [MIGRATION.md](MIGRATION.md) policy points and the
[MIGRATION2.md](MIGRATION2.md), [MIGRATION3.md](MIGRATION3.md) and [MIGRATION4.md](MIGRATION4.md)
amendments. 34 playbooks, now that the legacy tree is fully retired and `_personal/` is gone
with it:

| Category | Count | Meaning |
|----------|-------|---------|
| [Multi-user](#multi-user-34) | 34 | Root-owned paths, `/etc` drop-ins, verified as an unprivileged uid |
| [Effectively shared](#effectively-shared-0) | 0 | Legacy, but apt/system paths only — nothing lands in a `$HOME` |
| [Mixed](#mixed--shared-install-personal-tail-0) | 0 | Shared install plus a tail that benefits only the invoker |
| [Personal only](#personal-only-0) | 0 | The whole install lands in one `$HOME` or one account |

The repo is entirely multi-user now, and the balance moved in steps rather than gradually: a
migrated playbook is a *new* file, so during a migration both generations are counted, and the
total drops back when the originals are retired. That has happened four
times, and all four migrations are finished: `tool/` after MIGRATION.md, all thirteen of
`cloud-cli/` after MIGRATION2.md, all seven of `container/` after MIGRATION3.md, and all three
of `core/` after MIGRATION4.md. None of the four directories still exists — nothing named
`core/`, `tool/`, `cloud-cli/`, `container/`, `services/` or `gui-tools/` remains anywhere in the
repo, and now neither does `_personal/` (see [Retired: `_personal/`](#retired-_personal)). The
total held at 40 across `container/`'s retirement because seven successors replaced
exactly seven originals, then dropped to 37 when three more `core/` playbooks were deleted
outright with no successor at all (see below), then rose back to 40 as MIGRATION4.md's three
`_multi-user/core/` successors were written and verified against `localhost` — with their
`core/` originals not yet retired, so for a time both generations were counted, the same way the
first three migrations were counted mid-flight. It went back to 37 once those three originals
were retired (2026-08-16): three successors replaced exactly three originals, the same 1:1
arithmetic every migration here has held to. It dropped once more the same day, to 34, when
`_personal/`'s three playbooks were retired outright with no successor at all — the same shape
as the `core/` drop to 37, not a migration's 1:1 replacement. Fifteen playbooks in total
have now gone the deleted-rather-than-migrated way: `services/vault.yml`, `services/n8n.yml`,
`services/jellyfin.yml` and `services/freshrss.yml` (see
[Retired: `services/`](#retired-services)); `core/homebrew.yml`, which was
deleted once the migrations left it with no dependents (see
[Retired: `core/homebrew.yml`](#retired-corehomebrewyml)); `core/golang.yml` and
`core/rust.yml`, which were out of scope for a workstation that runs AI coding agents (see
[Retired: `core/golang.yml` and `core/rust.yml`](#retired-coregolangyml-and-corerustyml));
`container/krew.yml`, the first casualty of [MIGRATION3.md](MIGRATION3.md), dropped because a
plugin manager with a shared root can be read by every account and written by none (see
[Retired: `container/krew.yml`](#retired-containerkrewyml)); `gui-tools/vscode.yml`, a GUI
editor on a box whose work arrives over SSH, which took its directory with it (see
[Retired: `gui-tools/`](#retired-gui-tools)); `core/disable-rsyslog.yml` and `core/x11vnc.yml`,
a log-hygiene task with no pipeline left to justify it and a VNC desktop nobody drives (see
[Retired: `core/disable-rsyslog.yml` and `core/x11vnc.yml`](#retired-coredisable-rsyslogyml-and-corex11vncyml));
`services/samba.yml` → `core/samba.yml`, which moved once (2026-08-10) on the strength of an
exception to the `services/` retirement and was deleted anyway once that exception stopped
holding (2026-08-14) — see [Retired: `core/samba.yml`](#retired-coresambayml); and, last,
`_personal/ai-agent/claude-code.yml`, `nanoclaw.yml` and `vertex-ai-proxy.yml`, retired the same
day for scope rather than defect — per-identity work that belongs to the account it's for, not
to a shared workstation-provisioning repo — see [Retired: `_personal/`](#retired-_personal).

The legacy tree is empty, and now so is the tree that stood opposite it. There are no more
`hosts: localhost`, `connection: local` playbooks left to classify as personal in *execution
model* but shared in *outcome* — that emptied out with `core/` — and there is no longer a
staging tree for playbooks that are personal **by design**, either: `_personal/` filled that role
from MIGRATION3.md onward and is retired now (see [Retired: `_personal/`](#retired-_personal)),
so per-identity work has no home in this repo at all, rather than a separate one.
`_multi-user/` is the only underscore tree left. Its leading underscore has meant "staging,
sorts apart from the live single-user directories it will replace" since MIGRATION.md; now that
none of those directories exist — and there is no `_personal/` left to distinguish it from
either — the distinction it marks is gone too. Renaming it is a deliberate, separate decision
this document leaves open rather than folds in here, per
[MIGRATION4.md's known follow-ups](MIGRATION4.md#known-follow-ups), which no longer needs to ask
whether `_personal/` would want the same treatment — there is no `_personal/` left to ask.

### Multi-user (34)

All of `_multi-user/tools/` (11), all of `_multi-user/cloud-cli/` (13), all of
`_multi-user/container/` (7) and all of `_multi-user/core/` (3 — `core-tools.yml`, `nodejs.yml`,
`mise.yml`, written and verified against `localhost` by MIGRATION4.md; their `core/` originals
were deleted on 2026-08-16 once every successor was verified, the same gate `tool/`,
`cloud-cli/` and `container/` passed before them). Each uses
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

### Effectively shared (0)

Empty now. `core/nodejs.yml` and `core/core-tools.yml` were the last two rows, and both left on
2026-08-16 once [MIGRATION4.md](MIGRATION4.md) retired `core/`. Before them, this category was
mostly `cloud-cli/`; those seven playbooks were migrated and their originals deleted,
`services/jellyfin.yml` left with the rest of `services/`, `gui-tools/vscode.yml` left with
[its directory](#retired-gui-tools), and `container/devcontainers.yml` was migrated to
[`_multi-user/container/devcontainers.yml`](_multi-user/container/README.md#devcontainersyml)
and deleted with the rest of `container/`. `core/disable-rsyslog.yml` left the category the same
day by a different route —
[retired](#retired-coredisable-rsyslogyml-and-corex11vncyml) rather than migrated, out of scope
rather than unsafe — and `core/agent-base.yml` joined from the opposite direction that same day:
renamed `core/core-tools.yml` and cut down to its one `apt install` task once SSH, Avahi,
logind, journald, hostname and IPv6 handling were all peeled off. Both `core/nodejs.yml` and
`core/core-tools.yml` had already gained verified `_multi-user/core/` successors
([MIGRATION4.md](MIGRATION4.md)), counted under [Multi-user](#multi-user-34) above, before their
originals were retired — the same order every other row that ever left this category by
migration has followed.

### Mixed — shared install, personal tail (0)

Empty now. `core/mise.yml` was the last row, and it left on 2026-08-16 once
[MIGRATION4.md](MIGRATION4.md) retired `core/`, the same way `container/` had already emptied
three quarters of this category on 2026-08-14: `docker`, `podman`, `kubectl`, `helm`, `kind` and
`minikube` were six of its eight rows, each a shared install with a `~/.bashrc` block or a
`$USER` group add on the end, and all six left by being [migrated](MIGRATION3.md) — the
completions moved to `/etc/bash_completion.d` and the group add became `docker_users`.
`core/golang.yml` left earlier the other way: [retired](#retired-coregolangyml-and-corerustyml)
rather than fixed, since a toolchain nobody here compiles with was not worth un-mixing.
`core/samba.yml` [retired](#retired-coresambayml) the same way on 2026-08-14, a service scoped
out of the repo entirely being no more worth un-mixing. `core/mise.yml` had already gained an
unmixed `_multi-user/core/mise.yml` successor ([MIGRATION4.md](MIGRATION4.md)) that moves the
activation line to `/etc/profile.d/mise.sh`, counted under [Multi-user](#multi-user-34) above,
before the original was retired — the same order every other row in this category's history has
followed.

### Personal only (0)

Empty now, and permanently rather than provisionally. The three playbooks that lived here —
`_personal/ai-agent/claude-code.yml`, `vertex-ai-proxy.yml` and `nanoclaw.yml` — left by
retirement, not migration, and there is no `_personal/` left for a future personal-only playbook
to land in (see [Retired: `_personal/`](#retired-_personal)). That makes nine playbooks in total
that have left this category without being fixed in place: `core/homebrew.yml` was
[retired](#retired-corehomebrewyml) — it had been the root cause of four other entries here,
`cloud-cli/{gcx,influx,jira,vault}-cli.yml`, all `brew install` as `lookup('env', 'USER')`, until
wave 3 of MIGRATION2.md moved those to root-owned paths — `core/rust.yml` was
[retired with `core/golang.yml`](#retired-coregolangyml-and-corerustyml) as out of scope,
`container/krew.yml` was [retired](#retired-containerkrewyml) as per-user by design rather than
by defect, `core/ssh-key-setup.yml` became
[`setup-passwordless-ssh.sh`](#passwordless-ssh-setup), since a playbook whose every task was a
`chmod` inside the invoker's own `~/.ssh` was never getting anything from Ansible, `core/x11vnc.yml`
was [retired](#retired-coredisable-rsyslogyml-and-corex11vncyml) as out of scope for a box whose
work arrives over SSH, the three `_personal/ai-agent/` playbooks named above were
[retired](#retired-_personal) the same way — out of scope, per-identity work that belongs to the
account it's for rather than to this repo — and `core/agent-base.yml` left the category the one
way none of the others did: neither retired nor given an explicit user list, but stripped of the
tasks that made it personal in the first place. Renamed `core/core-tools.yml` (2026-08-14), it
kept only the `apt install` task and lost the `~/.xprofile`, `~/.xsessionrc` and three
`~/.bashrc` blocks along with it — the removed tasks are recoverable from git history
(`git log --all --full-history -- core/agent-base.yml core/core-tools.yml`).

Nothing is left to fix in place here, and by design nothing new can land in this category again:
a playbook that would be "personal only" is out of scope for this repo entirely now, the same
call [Retired: `_personal/`](#retired-_personal) made explicit rather than something MIGRATION.md's
explicit-user-list fix would apply to.

