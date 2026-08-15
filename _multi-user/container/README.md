# Container & Kubernetes Playbooks (multi-user workstations)

Standalone playbooks that install container and Kubernetes tooling on a **shared** Ubuntu
workstation. They are the multi-user successors to `container/`, which was retired on
2026-08-14 once all seven were verified. See
[MIGRATION3.md](../../MIGRATION3.md) for the policy and the per-tool plan.

Run from `_multi-user/`:

```bash
ansible-playbook container/<tool>.yml -e host=<inventory host or group>
```

## Conventions

These playbooks follow the same rules as [`tools/`](../tools/README.md) and
[`cloud-cli/`](../cloud-cli/README.md) — root-owned system paths, pinned versions, no
writes to any `$HOME`, and a closing check that runs the tool as an arbitrary uid
(`setpriv --reuid=65534`) rather than as the connecting account. Three rules matter
specifically here, because this directory installs *runtimes* rather than clients:

1. **A privilege grant takes an explicit list and defaults to empty.** Adding an account
   to the `docker` group, or enabling `loginctl` lingering for it, is a grant made to a
   named person — not part of installing software. No playbook here grants anything
   unless you name the accounts, and none of them ever infers the account from whoever
   ran the playbook. See [Grants](#grants).
2. **Per-user runtime state belongs to the user.** `~/.kube/config`, `~/.minikube/`,
   `~/.docker/`, `~/.local/share/containers` — these appear the first time an account
   *uses* a tool, and it is correct that they are per-account. No playbook here creates,
   shares, or pre-populates them, including for the connecting account.
3. **Verification proves an unprivileged account can run the client, not that a cluster
   exists.** Every playbook ends by exercising the tool as uid 65534. What that can prove
   varies by tool and is stated per playbook below; where a daemon or a cluster is the
   obstacle, the check is deliberately modest rather than skipped.

## Grants

Two of these playbooks can hand out access that the installation itself does not need.
Both take an explicit list, both default to **empty**, and both are **additive** — an
account you leave out keeps whatever it already has, because revoking access should be a
deliberate act rather than a side effect of running with a shorter list.

| Variable | Playbook | What it grants | Worth |
| --- | --- | --- | --- |
| `docker_users` | `docker.yml` | membership of the `docker` group | **equivalent to passwordless root** on this host |
| `podman_linger_users` | `podman.yml` | `loginctl enable-linger` | the account's user services survive logout |

Both accept a comma-separated string or a YAML list — the same shape every named-account var in
this repo takes:

```bash
ansible-playbook container/podman.yml -e host=ws01 -e podman_linger_users=alice,bob
```

> **Quoting matters.** `-e podman_linger_users="alice, bob"` splits on whitespace at the
> shell and binds only `alice,`; a trailing comma drops an account the same way. Each
> playbook prints the accounts it is about to act on before it acts — read that line.

## The `xhost` line is gone

`container/docker.yml` and `container/podman.yml` appended `xhost +local:docker` /
`xhost +local:podman` to the invoking account's `~/.bashrc`, which loosened X server
access control on every interactive shell that account opened, silently, from a playbook
whose job was installing a container runtime. **Neither successor does this, and nothing
replaces it** (MIGRATION3.md B5, decided 2026-08-14).

What that costs: a containerised GUI application no longer reaches the host X server just
because the account once ran the playbook. An account that wants that runs `xhost` itself,
per session, having decided to:

```bash
xhost +local:            # grants local connections until the X session ends
```

Note that removing a playbook does not remove what it already wrote. Accounts that ran the
old playbooks still carry the line in their `~/.bashrc`, and no playbook here will take it
out — deleting it is a manual, per-account cleanup.

## devcontainers.yml

Installs the Dev Containers CLI into npm's global (root-owned) prefix.

| Path | Contents |
| --- | --- |
| `<npm prefix>/bin/devcontainer` | the CLI entry point |
| `<npm prefix>/lib/node_modules/@devcontainers/cli` | the package |

The npm prefix is **read at run time**, not assumed: an apt-installed `nodejs` defaults it
to `/usr/local`, a NodeSource one to `/usr`. Both are root-owned, but hardcoding either
breaks the other host.

**Prerequisite:** system-wide Node.js. The playbook fails early if `node` resolves outside
`/usr/bin` or `/usr/local/bin`, which is what a per-user version manager (nvm, fnm, mise)
looks like — a global npm install under that shim would land in one account's home
directory instead of a system path.

**What changed versus `container/devcontainers.yml`.** The source installed
`@devcontainers/cli@latest` and guarded on `which devcontainer`, so it installed whichever
version was newest the day it first ran and then never moved again — which is why this
host sat on 0.87.0 while upstream was on 0.88.0. The version is now pinned and the guard
compares the *installed version*, so bumping the pin actually replaces the package.

**It needs Docker earlier than you would expect.** Even `devcontainer read-configuration`,
which looks like pure config parsing, shells out to `docker ps` to look for an existing
container — so it exits 1 for any account outside the `docker` group, printing only its
banner, with the real cause visible solely under `--log-level trace`. On a host where
nobody has been granted `docker_users`, every subcommand except `--help` and `--version`
will fail. That is also why this playbook's unprivileged check is `--help`: there is no
subcommand that does real devcontainer work without a container runtime.

Version override:

```bash
ansible-playbook container/devcontainers.yml -e host=ws01 -e devcontainers_cli_version=0.88.0
```

## podman.yml

Installs `podman` and `podman-compose` from the Ubuntu archive.

| Path | Contents |
| --- | --- |
| `/usr/bin/podman` | from the `podman` package |
| `/usr/bin/podman-compose` | from the `podman-compose` package |
| `/etc/containers/` | shared configuration, shipped by the packages |

Podman is rootless: each account gets its own containers, images and storage under
`~/.local/share/containers`, nothing is shared between accounts, and **no group membership
is needed** — unlike Docker, which needs a root-equivalent grant to be usable at all.

**What changed versus `container/podman.yml`.** Both packages are pinned with
`allow_downgrade` and verified after install; facts are gathered; the `xhost` line is
[gone](#the-xhost-line-is-gone); and `loginctl enable-linger`, which the source ran for
`lookup('env', 'USER')`, is now the explicit `podman_linger_users` list that defaults to
empty. Lingering is also now idempotent — the source playbook ran the command
unconditionally under `changed_when: false`, which hid its effect rather than avoiding it.

**Rootless podman needs a subuid/subgid range, and it is per-account.** `useradd`
allocates one by default; `adduser --system`, cloud-init and LDAP often do not, and
rootless podman then fails for that account in a way that looks like a podman bug (the
error names `newuidmap`, not the missing range). The playbook asserts a range exists in
both `/etc/subuid` and `/etc/subgid` for every account named in `podman_linger_users`, and
fails with the remedy before granting anything:

```bash
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 <account>
```

Verification is `podman --version` as uid 65534 — modest by design, because nearly every
other subcommand reaches for a container store, and `nobody` has no subuid range of its
own. It runs with a scratch `HOME`, which is not optional: podman stats `$HOME/.config`
before doing anything at all, so without one even `--version` fails as
`stat /root/.config: permission denied`.

Version overrides — these pins are **release-specific**, so check `apt-cache policy` on
the target before bumping:

```bash
ansible-playbook container/podman.yml -e host=ws01 \
  -e podman_version=5.7.0+ds2-3build1 -e podman_compose_version=1.5.0-2
```

## docker.yml

Installs Docker Engine from `download.docker.com`.

| Path | Contents |
| --- | --- |
| `/usr/bin/docker` | the CLI |
| `/usr/libexec/docker/cli-plugins/` | `buildx` and `compose`, shared by every account |
| `/etc/apt/sources.list.d/docker.sources` | repository definition, signing key inline |

> **A fresh run grants nobody access to the daemon, and that is deliberate.** The engine is
> installed and running; no account can talk to it until you name accounts in `docker_users`.
> `container/docker.yml` added whoever ran it, so this *will* look like a regression. It is
> not one — see [Grants](#grants).

```bash
ansible-playbook container/docker.yml -e host=ws01 -e docker_users=alice,bob
```

Members must log out and back in for the new group to take effect.

**If you do not want a root-equivalent grant,** two real alternatives: rootless Docker, via
the `docker-ce-rootless-extras` package this playbook installs but does not configure (each
account runs `dockerd-rootless-setuptool.sh install` for itself), or
[podman](#podmanyml), which needs no grant at all.

**What changed versus `container/docker.yml`.** All five packages are pinned; the repository
uses `deb822_repository` with Docker's signing key pinned inline by content (it carries no
expiry) instead of a `get_url` that re-downloaded with `force: true` on every run;
architecture comes from facts rather than a hardcoded `arch=amd64`; the auto-named
`download_docker_com_linux_ubuntu.list` the source playbook left behind is removed; the
`xhost` line is [gone](#the-xhost-line-is-gone); and the group membership is the explicit
`docker_users` list.

Verification does something the source playbook never did: as uid 65534 it runs the CLI and
the `buildx` plugin (proving `/usr/libexec/docker/cli-plugins` is reachable by an ordinary
account, which is the actual multi-user question for Docker), and then asserts that the same
account is **refused** at the socket. A run where an ungranted account can drive the daemon
fails.

The pins embed the Ubuntu codename (`5:29.7.2-1~ubuntu.26.04~resolute`), so they are not
portable across releases:

```bash
ansible-playbook container/docker.yml -e host=ws01 \
  -e docker_version=5:29.7.2-1~ubuntu.26.04~resolute \
  -e containerd_version=2.3.3-1~ubuntu.26.04~resolute
```

## kubectl.yml

Installs kubectl from `pkgs.k8s.io`, **and pins apt so it stays installed.**

| Path | Contents |
| --- | --- |
| `/usr/bin/kubectl` | the client |
| `/etc/apt/sources.list.d/kubernetes.sources` | repository definition (`v1.36` stream) |
| `/etc/apt/preferences.d/kubectl` | the pin that resolves the collision below |
| `/etc/bash_completion.d/kubectl` | shared completion, generated from the binary |
| `/etc/profile.d/kubectl.sh` | the `k` alias, with completion wired to it |
| `/usr/bin/kubectx`, `/usr/bin/kubens` | from the Ubuntu archive's `kubectx` package |

**Two repositories publish a package called `kubectl`, and without the pin the wrong one
always wins.** `packages.cloud.google.com` — added by `cloud-cli/gcloud-cli.yml`, which does
not install kubectl and has no idea it is involved — publishes a Cloud SDK dispatcher build
with an **epoch** (`1:580.0.0-0`). An epoch outranks every version upstream will ever publish.
Both ship `/usr/bin/kubectl` and neither declares `Conflicts`, so exactly one can be installed,
and on any host that has ever run `gcloud-cli.yml` it was Google's — which the source
playbook installed while reporting success. The giveaway is a `-dispatcher` suffix in
`kubectl version --client`.

Installing the right version once is not enough: the next unrelated `apt upgrade` takes it
straight back. `/etc/apt/preferences.d/kubectl` pins the `pkgs.k8s.io` origin at priority
**1001** — above 1000, which is what permits apt to move *backwards* across the epoch. The
playbook asserts on every run that `apt-cache policy` reports the pinned version as the
candidate, so the protection is tested rather than assumed.

**Deleting that preferences file re-opens the collision.**

The stream is part of the pin: moving to `v1.37` means editing `kubectl_stream` as well as
`kubectl_version`. As of 2026-08-14 the `v1.36` stream carries exactly one version and no
`v1.37` stream exists.

The repository's signing key **expires 2026-12-29**, so it is fetched each run and only its
fingerprint is pinned. When it rotates, the run fails with instructions rather than trusting
a new key silently — that is intended; verify the new fingerprint and update it deliberately.

```bash
ansible-playbook container/kubectl.yml -e host=ws01 -e kubectl_version=1.36.3-1.1
```

**kubectx and kubens are the partial exception to [krew's retirement](../../README.md#retired-containerkrewyml).**
That note named `ctx` and `ns` as things a plain binary in `/usr/local/bin` could bring
back; this playbook does it more simply than that implies. The Ubuntu archive already
carries a `kubectx` package — one source, no vendor collision, no repository or key to
add — that installs `/usr/bin/kubectx` and `/usr/bin/kubens` directly, with completions
under the paths `bash-completion` already reads. Pinned like everything else here
(`kubectx_version`), even though nothing forces the version the way `kubectl_version`
does. What does **not** come back is krew itself, or running these as `kubectl ctx` /
`kubectl ns` — the package names the binaries `kubectx` and `kubens`, not `kubectl-ctx` /
`kubectl-ns`, so kubectl's plugin discovery never sees them.

```bash
ansible-playbook container/kubectl.yml -e host=ws01 -e kubectx_version=0.9.5-2build1
```

## helm.yml

Installs Helm from `packages.buildkite.com/helm-linux/helm-debian`.

| Path | Contents |
| --- | --- |
| `/usr/bin/helm` | the binary |
| `/etc/apt/sources.list.d/helm.sources` | repository definition, signing key inline |
| `/etc/bash_completion.d/helm` | shared completion, generated from the binary |

> **This installs Helm 4, where the source playbook may have installed Helm 3.**
> `container/helm.yml` was unpinned, so what it installed depended on the day it ran and
> nothing recorded which. Pinning it was a deliberate choice of major version, taken because
> nothing in this repo templates a chart and Helm was not installed on any host here.

The 3.x line is still published from the same repository under the same package name, so the
fallback is one flag:

```bash
ansible-playbook container/helm.yml -e host=ws01 -e helm_version=3.21.3-1
```

The playbook prints a **MAJOR VERSION CHANGE** warning when a run would move between 3.x and
4.x in either direction.

**What changed versus `container/helm.yml`.** The version is pinned and verified; the
repository uses `deb822_repository` with the packagecloud key pinned inline (it carries no
expiry) instead of `get_url` plus a `shell: gpg --dearmor` that reported `changed` every run;
the completion moved out of one account's `~/.bashrc` into `/etc/bash_completion.d`; and
verification is real offline work — as uid 65534 it lints and renders a small chart the
playbook writes, rather than running `helm version` as the connecting account.

## kind.yml

Installs the `kind` release binary.

| Path | Contents |
| --- | --- |
| `/usr/local/bin/kind` | the binary, root-owned, mode 0755 |
| `/etc/bash_completion.d/kind` | shared completion, generated from the binary |

**What changed versus `container/kind.yml`.** The install guard compares the *reported
version* instead of asking whether the file exists — which is not a theoretical improvement:
the old guard left this host on kind 0.27.0 through five upstream releases, because once the
binary existed the playbook never replaced it. The download is now verified against the
published `kind-linux-<arch>.sha256sum`, the architecture comes from facts, and the
completion moved out of one account's `~/.bashrc` into `/etc/bash_completion.d`.

```bash
ansible-playbook container/kind.yml -e host=ws01 -e kind_version=0.32.0
```

## minikube.yml

Installs the `minikube` release binary.

| Path | Contents |
| --- | --- |
| `/usr/local/bin/minikube` | the binary, root-owned, mode 0755 |
| `/etc/bash_completion.d/minikube` | shared completion, generated from the binary |

**What changed versus `container/minikube.yml`.** Same three fixes as `kind.yml` (version-aware
guard, checksum verification, architecture from facts, completion to `/etc`), plus one
removal: `minikube config set driver docker` is **gone**. It ran with `become: no` and wrote
`~/.minikube/config/config.json` for whoever happened to run the playbook, so the "default
driver" it set was a default for exactly one account.

**No driver default is set system-wide, and that is a decision.** `MINIKUBE_DRIVER` was tested
and minikube really does read it — but minikube already auto-selects the docker driver when
Docker is present, so a shared `MINIKUBE_DRIVER=docker` would be a no-op for every account that
can use Docker, and actively wrong for every account that cannot: it would push them at the one
driver they have no access to, instead of letting minikube offer podman. Each account sets its
own, once:

```bash
minikube config set driver docker    # or podman
```

**minikube is expensive per account.** Every account that runs `minikube start` gets its own
`~/.minikube` with its own certificates and its own copy of the kicbase image — gigabytes each,
with no shared mode. On a workstation with several agent accounts, budget for it. `minikube
delete` reclaims it.

```bash
ansible-playbook container/minikube.yml -e host=ws01 -e minikube_version=1.38.1
```

## Status

| Playbook | Successor to | Pinned | Status |
| --- | --- | --- | --- |
| `devcontainers.yml` | `container/devcontainers.yml` | 0.88.0 | Verified (localhost) |
| `podman.yml` | `container/podman.yml` | podman 5.7.0+ds2-3build1, podman-compose 1.5.0-2 | Verified (localhost) |
| `docker.yml` | `container/docker.yml` | docker-ce 5:29.7.2-1~ubuntu.26.04~resolute, containerd.io 2.3.3, buildx 0.36.1, compose 5.4.0 | Verified (localhost) |
| `kubectl.yml` | `container/kubectl.yml` | 1.36.3-1.1 | Verified (localhost) |
| `helm.yml` | `container/helm.yml` | 4.2.3-1 | Verified (localhost) |
| `kind.yml` | `container/kind.yml` | 0.32.0 (was 0.27.0) | Verified (localhost) |
| `minikube.yml` | `container/minikube.yml` | 1.38.1 | Verified (localhost) |

All seven are migrated, and these are now the only generation: `container/` was deleted on
2026-08-14 once every successor was verified, so the "Successor to" column names files that
exist only in git history (`git log --diff-filter=D -- container/`). `container/krew.yml` was
[retired](../../README.md#retired-containerkrewyml) rather than migrated, so there is no
`krew.yml` here. What the retirement gate did *not* cover is below, and it is worth reading:
the successors were verified against a real host, but never against a *remote* one — see
[MIGRATION3.md](../../MIGRATION3.md#known-follow-ups).

**`kind` and `minikube` are only as multi-user as the `docker` group is.** Both drive Docker,
so each installs a binary every account can execute and that no account outside `docker_users`
can use for anything. That is the honest state of those tools, not a defect in the migration.

"Verified (localhost)" carries the same two caveats as everything else in `_multi-user/`: the
runs were made under ansible-core 2.20 with `ansible_connection=local`, so they exercise
neither the 24.04 control node nor the SSH path. `ws01`/`ws02` have never been provisioned by
either generation.
