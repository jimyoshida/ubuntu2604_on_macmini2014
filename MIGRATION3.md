# Multi-User Workstation Container Playbook Migration

Policy and procedure for migrating the container and Kubernetes playbooks from `container/` to
`_multi-user/container/`.

**Status: planned.** 0 of 8 source playbooks migrated. No playbook has been written yet; the
decisions in [Notes on the four that need a decision](#notes-on-the-four-that-need-a-decision)
come first. See [Migration status](#migration-status).

This document is the third in the series. [MIGRATION.md](MIGRATION.md) covered `tool/` →
`_multi-user/tools/` and [MIGRATION2.md](MIGRATION2.md) covered `cloud-cli/` →
`_multi-user/cloud-cli/`; both are complete and both directories are gone. Everything in them
still applies: the [prerequisites](MIGRATION.md#prerequisites) (inventory, `ubuntu` remote
user, passwordless sudo), the ten [policy](MIGRATION.md#policy) points, the [playbook
skeleton](MIGRATION.md#playbook-skeleton), the [install mechanism decision
order](MIGRATION.md#install-mechanism-decision-order), and MIGRATION2's five
[amendments](MIGRATION2.md#policy-amendments) A1–A5. This document records only what is
*different* about `container/`, plus the per-tool plan.

## Background

`container/` is the last of the three tool-installing directories in the legacy tree, and it is
the one where the multi-user question is least about *reach*. Six of its eight playbooks already
put the binary somewhere every account can execute it — apt packages and `/usr/local/bin`. What
they get wrong is everything around the binary.

MIGRATION.md's three causes and MIGRATION2's two recur, and three more are new:

1. **Homebrew ownership.** Does not apply. No playbook here uses `brew`, and
   [`core/homebrew.yml` is retired](README.md#retired-corehomebrewyml).
2. **Per-user shell profiles.** The dominant cause here. Four playbooks
   (`kubectl`, `helm`, `kind`, `minikube`) write a `blockinfile` to
   `/home/{{ <tool>_user }}/.bashrc`, and two more (`docker`, `podman`) `lineinfile` an
   `xhost` call into `~/.bashrc`. Six of eight, more than either previous directory.
3. **Per-user install prefixes.** `krew.yml` installs into `~/.krew` and prepends
   `$HOME/.krew/bin` to `PATH`. This is krew's designed shape, not a defect in the playbook —
   see [#7's note](#notes-on-the-four-that-need-a-decision).
4. **Install-time `lookup('env', ...)` baked into shared state** (MIGRATION2 cause 4). Seven of
   eight playbooks open with `<tool>_user: "{{ lookup('env', 'USER') }}"`. Nothing renders it
   into a *shared* file the way `jenkins-cli.yml` did, but every one of them decides whose home
   directory and whose account gets the work from the invoker's environment.
5. **Secrets** (MIGRATION2 cause 5). Does not apply. Nothing here has a token; a kubeconfig is
   the closest thing, and no playbook writes one.
6. **NEW — privilege grants shipped as installation steps.** `docker.yml` task 5 adds the
   invoker to the `docker` group. Membership in that group is root-equivalent: the socket it
   grants will start a container with the host filesystem bind-mounted, as root. `podman.yml`
   task 2 runs `loginctl enable-linger` for the invoker, which is far milder but is still a
   per-account grant rather than an install. Neither is a thing that can be fixed by moving it
   to `/usr/local`. The multi-user answer is an explicit list and a default of *nobody* — see
   [B1](#policy-amendments).
7. **NEW — per-user runtime state the tool creates for itself.** `~/.kube/config`,
   `~/.minikube/` (a whole cluster profile, with certificates and a multi-gigabyte kicbase
   image), `~/.docker/`, `~/.krew/`. Unlike a credential file, this state appears the first
   time an account *uses* the tool, and it is correct that it is per-user. The rule that
   follows is a prohibition, not a task: a migrated playbook must not pre-create it, must not
   share it, and must not write one account's copy on behalf of another. `minikube.yml` task 6
   (`minikube config set driver docker`, `become: no`) breaks this — see
   [B2](#policy-amendments).
8. **NEW — a security-relevant side effect hidden in a shell profile.** `docker.yml` task 6 and
   `podman.yml` task 3 append `xhost +local:docker` / `xhost +local:podman` to `~/.bashrc`.
   Whatever this grants, it grants it by loosening X server access control on every interactive
   shell, silently, in a playbook whose stated job is installing a container runtime. What it
   actually grants has to be established before deciding where it goes — see
   [B5](#policy-amendments).

There is also a defect class that is not about multi-user reach at all and that this directory
has worse than either predecessor: **version discipline**. `kind.yml` and `minikube.yml` guard
on `stat.exists` (policy point 6 — a version bump silently no-ops, which is why this host still
runs kind 0.27.0 from a playbook that could have been re-run any time). `kubectl.yml`,
`helm.yml`, `docker.yml` and `podman.yml` pin nothing at all. `devcontainers.yml` installs
`@latest` and then guards on `which devcontainer`, so it installs the newest version once and
never again. `krew.yml` downloads `releases/latest`. Not one of the eight pins a version, and
five of eight cannot upgrade what they installed.

## Scope

| | |
| --- | --- |
| Source | `container/*.yml` (8 playbooks) + `container/README.md` |
| Target | `_multi-user/container/*.yml` |
| Applies to | New multi-user workstation builds |
| Control node | Ubuntu 24.04 (ansible-core **2.16**) **or** Ubuntu 26.04 (ansible-core 2.20) |
| Targets | Ubuntu 26.04 (`localhost`, `ws01`, `ws02`), Python 3.14 |

The 2.16 floor from [MIGRATION2's scope note](MIGRATION2.md#scope) is unchanged and unrelaxed:
a playbook may use nothing newer, and must still be correct on 2.20. Nothing this plan calls for
postdates `deb822_repository` (2.15), which the migrated `cloud-cli/` playbooks already use.

**On the target naming.** `_multi-user/container/`, singular, matching the source directory —
same reasoning as `cloud-cli/`: the parent distinguishes them, so no plural is needed. The
leading underscore on `_multi-user/` still means staging.

**Out of scope:**

- `core/` and `gui-tools/` — what remains of the legacy tree after this migration. `core/` is a
  harder problem than any of the three tool directories (`agent-base.yml` and `x11vnc.yml` are
  desktop-session and VNC setup, which is per-identity in a way no relocation fixes), and
  `gui-tools/vscode.yml` is already an apt install with an unused `vscode_user` variable.
- `container/*` itself stays in place until its successors are verified, the same way `tool/`
  and `cloud-cli/` did. Retiring it is the last step, not the first.
- Running clusters. Every playbook here installs a client or a runtime; none creates a kind
  cluster, starts a minikube profile, or deploys a chart, and that stays true after migration.
  The same line `cloud-cli/` drew at "installs the client, configures no identity", this
  directory draws at "installs the runtime, runs no workload".
- Docker daemon configuration (`/etc/docker/daemon.json`), registry mirrors, storage drivers.
  The source playbooks touch none of it and this migration adds none.

## Policy amendments

MIGRATION.md's ten points and MIGRATION2's A1–A5 hold. These five (B1–B5) resolve what
`container/` raises and they do not.

**B1. A privilege grant takes an explicit list and defaults to empty. (amends A2)**
`docker` group membership and `loginctl enable-linger` are not installation, and they are not
configuration either — they are grants made to named accounts. Every one takes a play var:

```yaml
docker_users: []          # accounts to add to the docker group; root-equivalent
podman_linger_users: []   # accounts whose user services survive logout
```

Empty is the default and empty means *the playbook grants nothing*. This is the one place this
migration deliberately makes a playbook do less than its predecessor: `container/docker.yml` run
on a fresh host today produces a working `docker` for the invoker, and its successor run with no
`-e docker_users=...` produces a working daemon that the invoker cannot talk to. That is the
correct default on a shared box — a root-equivalent grant should be typed out, once, per
account, in the run record — and the README must say so in those words, because the first person
to hit it will read it as a regression.

Three corollaries:

- **Never `lookup('env', 'USER')`, and never default the list to the connecting account.** That
  is the `_personal/` lesson: the account Ansible connects as is an operator, not a
  beneficiary.
- **Grants are additive only.** `append: true`; a playbook that does not name an account must
  not remove that account's existing membership. Revoking is a deliberate act, not a
  side effect of running with a shorter list.
- **Say what the grant is worth.** The README states that `docker_users` is equivalent to
  passwordless root, and names the alternatives (rootless Docker via
  `docker-ce-rootless-extras`, already packaged; or podman, which needs no grant at all).

**B2. Per-user runtime state is created by the user, not by the playbook. (amends A3)**
A3 moved per-identity *setup commands* into the README. B2 extends it to per-account *runtime*
state, which is broader: no task in a migrated playbook may write, pre-create, or chown anything
under any account's `$HOME`, including the invoker's — not `~/.kube`, not `~/.minikube`, not
`~/.docker`, not `~/.krew`. `minikube config set driver docker` is the case in hand: it writes
`~/.minikube/config/config.json` for whoever ran the playbook and nobody else, so the "default
driver" it sets is a default for exactly one account.

Where a site-wide default genuinely is wanted, express it as A1 shared config in
`/etc/profile.d/<tool>.sh` — **and only after confirming the tool reads it**, by MIGRATION2's
negative-control method (set the name, set a plausible near-miss instead, compare the failures).
Three of the eight names checked in MIGRATION2 turned out not to be read by the tool that was
supposed to read them; assume this one is wrong until it is tested on the target.

**B3. Completions and aliases go to `/etc`, and are generated from the installed binary.**
Six `~/.bashrc` blocks become two kinds of file:

| Content | Destination | Why |
| --- | --- | --- |
| `<tool> completion bash` output | `/etc/bash_completion.d/<tool>`, written once at install time | Read by every account; costs no subshell at shell start |
| Aliases (`alias k=kubectl`) and `PATH` additions | `/etc/profile.d/<tool>.sh` | Not completion data; needs the `/etc/bash.bashrc` bootstrap |

Generate the completion file with the binary the playbook just installed and write the output —
do not copy `source <(kubectl completion bash)` into a shared file. The source playbooks' form
re-runs the tool on every interactive shell start, which is a per-shell subprocess for each of
six tools, and it breaks noisily for any account whose `PATH` does not yet have the binary.
Writing the generated file also makes the completion versioned with the install: it changes when
the pin changes, and shows up as `changed` when it does.

`bash-completion` becomes a task-1 prerequisite in each playbook, exactly as wave 3 of
MIGRATION2 settled it. The `/etc/profile.d` bootstrap in `/etc/bash.bashrc`
(`_multi-user/tools/modern-cli-tools.yml`) is a hard dependency for the alias half only.

**B4. Verification proves an unprivileged account can run the client — not that a cluster
exists. (amends A4)**
A4 was written for CLIs that cannot work unauthenticated. Here the obstacle is a *daemon or a
cluster* rather than a credential, and the guard asserts: an arbitrary uid can execute the
binary, discover its plugins and shared data, and reach its own offline code path. In A4's
preference order:

1. **Offline real work.** `helm template` on a chart the playbook writes, `helm lint`,
   `kubectl create deployment --dry-run=client -o yaml`, `kubectl apply --dry-run=client -f` on
   a manifest the playbook writes. Available for `kubectl` and `helm`; use it there.
2. **A subcommand that inspects the install itself.** `docker context ls` and
   `docker buildx version` (proves the CLI plugins in `/usr/libexec/docker/cli-plugins` are
   discoverable by a non-root account, which is the actual multi-user question for Docker),
   `kubectl krew list` against the shared root, `devcontainer --help`.
3. **`--version` alone.** `kind`, `minikube`, `podman`. Weakest, and it is what is available:
   nearly every other `kind`/`minikube` subcommand reaches for a container runtime.

Two additions specific to this directory:

- **Assert the negative for a grant.** Where a playbook grants access to a socket, the smoke
  test should also prove the grant *is* a grant: as uid 65534, `docker info` must fail with a
  permission error on `/var/run/docker.sock`. A run where an ungranted account can drive the
  daemon is a finding, not a pass. Match the error text, not merely a non-zero exit.
- **Rootless podman's real prerequisite is subuid/subgid, and it is per-account.** `podman` as
  uid 65534 cannot get past `newuidmap` — `nobody` has no range in `/etc/subuid`. So the useful
  multi-user check is not a smoke test at all: assert that every account in `podman_linger_users`
  has an entry in both `/etc/subuid` and `/etc/subgid`, and fail with the `usermod --add-subuids`
  remedy if not. `useradd` allocates ranges by default, but accounts created by other means
  (`adduser --system`, cloud-init, LDAP) often have none, and rootless podman fails for them in
  a way that looks like a podman bug.

**B5. Check for a colliding *package*, not just a colliding *repository*. (amends A5)**
A5 made the migrated playbooks agree with each other about keyring paths and
`sources.list.d` filenames. That is not sufficient here, and this host proves it: `kubectl` is
published by both `pkgs.k8s.io` (the repository `container/kubectl.yml` adds) and
`packages.cloud.google.com` (the repository `_multi-user/cloud-cli/gcloud-cli.yml` adds), under
the same package name, with no `Conflicts`/`Replaces` between them, and Google's carries an
epoch (`1:579.0.0-0`) that beats every version upstream will ever publish (`1.36.3-1.1`). The
two repository files do not collide at all; the packages do. Before adding any vendor
repository, check what else already provides the package name being installed:

```bash
cd _multi-user
ansible -m shell -a 'apt-cache policy <package>; apt-cache madison <package>' <host>
```

Where the collision is real, an unpinned `apt: name=<pkg> state=present` is not merely
unpinned — it installs from a different vendor than the repository the playbook just configured,
and reports success. See [#3's note](#notes-on-the-four-that-need-a-decision).

The `xhost` question belongs here too, as the one input this plan has deliberately not resolved:
**establish what `xhost +local:docker` grants before deciding what replaces it.** The `local`
family's name field may be ignored, in which case the line is equivalent to `xhost +local:` and
grants every local connection — a much wider grant than its name suggests — or it may add a
host entry that matches nothing and grant nothing at all. Test it with the negative control
(`xhost +local:docker` versus `xhost +local:nosuchthing`, then `xhost` to list) on a host with a
display, and record the answer here. The disposition follows from it: if it grants nothing,
delete it; if it grants everything local, it is a security decision that belongs in the README
under a `-e` flag, off by default, not in six accounts' `.bashrc`.

## Per-tool state, grants and shared config

The table to check a migrated playbook against. If it touches anything in the "Per-user state"
column, it is wrong; if it makes anything in the "Grant" column without an explicit list, it is
wrong.

| Tool | Per-user state (never touched) | Grant (explicit list, default empty) | Shared config (`/etc`) |
| --- | --- | --- | --- |
| `docker` | `~/.docker/config.json`, `~/.docker/contexts` | `docker` group membership — **root-equivalent** | CLI plugins in `/usr/libexec/docker/cli-plugins` (packaged) |
| `podman` | `~/.local/share/containers`, `~/.config/containers` | `loginctl enable-linger`; subuid/subgid ranges | `/etc/containers/*` (packaged) |
| `kubectl` | `~/.kube/config` | — | `/etc/bash_completion.d/kubectl`, `/etc/profile.d/kubectl.sh` (the `k` alias) |
| `helm` | `~/.config/helm`, `~/.cache/helm`, repo list | — | `/etc/bash_completion.d/helm` |
| `kind` | `~/.kube/config` (kind merges its context in) | needs `docker` group to do anything | `/etc/bash_completion.d/kind` |
| `minikube` | `~/.minikube/` — certs, profiles, kicbase image | needs `docker` group to do anything | `/etc/bash_completion.d/minikube`; `MINIKUBE_DRIVER` **if** verified per B2 |
| `krew` | `~/.krew` today; see [#8](#notes-on-the-four-that-need-a-decision) | — | `/etc/profile.d/krew.sh` — both `KREW_ROOT` and `PATH`, neither optional |
| `devcontainer` | none | — | npm global prefix, read at run time |

Two rows worth stating explicitly because they change what "multi-user" can mean:

- **`kind` and `minikube` are only as multi-user as the `docker` group is.** Both drive Docker.
  A perfectly migrated `kind.yml` installs a binary every account can execute and that no
  account outside `docker_users` can use for anything. That is not a defect in the migration —
  it is the honest state of the tool — but the README must say it, or the next person reads a
  "multi-user" playbook as a promise it cannot keep.
- **`minikube` per-account is expensive.** Each account that runs `minikube start` gets its own
  `~/.minikube` with its own copy of the kicbase image and its own certificates. On a shared
  workstation with several agent accounts that is gigabytes per account, and there is no shared
  mode to migrate it into. Worth a sentence in the README next to the disk it will use.

## Per-tool migration plan

Mechanism numbers refer to MIGRATION.md's [decision
order](MIGRATION.md#install-mechanism-decision-order).

| # | Playbook | Today | Target mechanism | Principal work |
| --- | --- | --- | --- | --- |
| 1 | `devcontainers.yml` | `npm install -g @latest` | (6) unchanged | pin; version-aware guard (`devcontainer --version`, not `which`); npm prefix read at run time per MIGRATION.md's `markdownlint` finding; unprivileged smoke test with a scratch `HOME` |
| 2 | `podman.yml` | apt | (1) unchanged | pin both packages; `gather_facts: true`; lingering → `podman_linger_users` per B1; subuid/subgid assertion per B4; drop the `xhost` line per B5 |
| 3 | `docker.yml` | vendor apt repo | (2) unchanged — `download.docker.com` | A5 cleanup (`deb822_repository`, arch from facts, no `force: true` re-download); pin the five packages; group add → `docker_users` per B1; negative-assert the socket per B4; drop the `xhost` line per B5 |
| 4 | `kubectl.yml` | vendor apt repo `v1.30` | (2) — bump the stream, **plus an apt preferences pin** | the package collision — see note; remove the stale `kubernetes.list`; completion + `k` alias to `/etc` per B3; `--dry-run=client` smoke test |
| 5 | `helm.yml` | vendor apt repo, unpinned | (2) unchanged — `packages.buildkite.com` | A5 cleanup, keeping the fingerprint assertion (`github-cli.yml`'s task 5/6 pattern is a direct fit); **pin — which lands Helm 4, see note**; completion to `/etc`; `helm template` smoke test |
| 6 | `kind.yml` | release binary, `stat.exists` guard | (3) unchanged | checksum from `kind-linux-<arch>.sha256sum`; arch from facts; version-aware guard; 0.27.0 → 0.32.0; completion to `/etc` |
| 7 | `minikube.yml` | release binary, `stat.exists` guard | (3) unchanged | as #6, plus drop `minikube config set driver docker` per B2 and decide on `MINIKUBE_DRIVER`; 1.35.0 → 1.38.1 |
| 8 | `krew.yml` | `curl \| sh` into `~/.krew` | (3)/(4) — shared `KREW_ROOT`, see note | the one genuine reach problem here; also the only playbook whose *shape* is in question |

### Notes on the four that need a decision

**`kubectl.yml` (#4) — the package collision, and the reason B5 exists.** Verified on
`localhost` on 2026-08-11:

```console
$ apt-cache policy kubectl
  Installed: 1:568.0.0-0
  Candidate: 1:579.0.0-0
     1:579.0.0-0  500  https://packages.cloud.google.com/apt cloud-sdk/main amd64 Packages
$ kubectl version --client
Client Version: v1.35.3-dispatcher
```

The repository `container/kubectl.yml` configures (`pkgs.k8s.io/core:/stable:/v1.30`) tops out
at `1.30.14-1.1`. The Google Cloud SDK repository — added by
`_multi-user/cloud-cli/gcloud-cli.yml`, which does not install `kubectl` and has no idea it is
involved — publishes a `kubectl` package with epoch `1:`, so it wins the candidate selection
unconditionally, forever. Task 5's `apt: name=kubectl state=present` therefore installs
Google's dispatcher build on any host that has ever run `gcloud-cli.yml`, and reports success.
Neither package declares `Conflicts` or `Replaces`; both ship `/usr/bin/kubectl`, so exactly one
of them can be installed and it is always the Google one. That is the state of this workstation
right now, and the `-dispatcher` suffix is the only visible trace.

Three ways out:

- (a) **Recommended.** Keep apt and pkgs.k8s.io, bump the stream to `v1.36`, pin the version
  (`1.36.3-1.1`), and write `/etc/apt/preferences.d/kubectl` pinning the pkgs.k8s.io origin at
  priority `1001`. The pin is what makes it stick: `apt install kubectl=1.36.3-1.1
  --allow-downgrades` installs it once regardless, but without a preferences entry the next
  `apt upgrade` on a host with the Google repo drags it straight back across the epoch. Priority
  above 1000 is required precisely because the correct version is "lower" than the incumbent.
- (b) Release binary from `dl.k8s.io` to `/usr/local/bin` (`kubectl` + a published `.sha256`,
  both confirmed present for `v1.36.3`). Simpler, no repository, no epoch fight — and wrong
  here, because it leaves Google's `/usr/bin/kubectl` installed and merely shadows it by `PATH`
  order. That is the exact shape of the Homebrew `PATH`-precedence follow-up this repo has been
  carrying since MIGRATION.md, and it should not be recreated deliberately.
- (c) Declare the Google `kubectl` the supported one and delete `kubectl.yml`. Defensible on a
  workstation that already installs `gcloud`, but it makes the Kubernetes client version a
  function of a Cloud SDK release, ties it to a repository that need not be present, and pulls
  in a 458 MB installed package to get one binary.

Whichever is chosen, remove `/etc/apt/sources.list.d/kubernetes.list` (the source playbook's
file, still present on this host and still pointing at the EOL `v1.30` stream) using the
"remove the single-user playbook's apt source" task the migrated `cloud-cli/` playbooks already
carry, and note that the stream is part of the pin: moving to `v1.37` means editing the URI, not
just the version string.

**`helm.yml` (#5) — pinning it is a major version bump.** The source playbook installs
`helm` unpinned from `packages.buildkite.com/helm-linux/helm-debian`, so it installs whatever is
newest, which as of 2026-08-11 is **4.2.3-1**; the repository also still carries the 3.x line
(3.21.3-1 latest). Anyone who ran the playbook before Helm 4 shipped has 3.x, anyone who runs it
today gets 4.x, and nothing records which. Pinning is therefore not a no-op decision: it is
choosing, on the record, which major version this repo installs. MIGRATION.md's step 4 says to
check in-repo consumers first —

```bash
grep -rn "helm\b" --include='*.yml' --include='*.md' . | grep -v '^_multi-user/'
```

— and there are none: nothing in this repo templates a chart, and Helm is not installed on this
host at all. Recommend **4.2.3-1**, stated explicitly in the README and the commit message as a
3→4 change, with the 3.x pin (`-e helm_version=3.21.3-1`) documented as the one-flag fallback
for anyone with Helm 3 charts. Helm 4 keeps the same vendor repository and package name, so the
fallback costs nothing to support.

**`krew.yml` (#8) — a per-user tool by design, not by defect.** krew's `KREW_ROOT` defaults to
`~/.krew`, and `kubectl krew install` writes into `$KREW_ROOT/store` with `$KREW_ROOT/bin` on
`PATH`. A root-owned shared root is possible (`KREW_ROOT=/usr/local/krew`) and every account can
then *run* the installed plugins, but no unprivileged account can add one — which is the same
shape as the Homebrew problem this repo spent two migrations removing.

Shared installation is supported upstream, not a workaround: krew's own [Advanced
Configuration](https://krew.sigs.k8s.io/docs/user-guide/advanced-configuration/) page documents
`KREW_ROOT` for exactly this and uses `/usr/local/krew` as its example. It was rehearsed on
2026-08-11 against krew v0.5.0 with a scratch root, made read-only to stand in for a root-owned
tree, and the behaviour is as [B4](#policy-amendments) needs it:

| Action from a non-writable root | Result |
| --- | --- |
| `kubectl ctx`, `kubectl ns` (running a plugin) | works — plain `PATH` discovery, no krew involved |
| `kubectl krew list` | works — reads `$KREW_ROOT/receipts` |
| `kubectl krew search` | works — reads the local index, does not force a refresh |
| `kubectl krew version` | works — and prints the resolved `BasePath`, which is what the smoke test should assert |
| `kubectl krew install <plugin>` | **fails, rc 1** — the index `git fetch` hits `Permission denied` before anything is written |
| anything, with a scratch `HOME` | **writes nothing to `$HOME`** |

Four mechanics that follow from that rehearsal and belong in the playbook:

- **`$KREW_ROOT/bin` holds absolute symlinks** into `$KREW_ROOT/store/<plugin>/<version>/`. The
  tree is therefore not relocatable: install with `KREW_ROOT` already set to the final path,
  never build it under `/var/tmp` and move it.
- **`KREW_ROOT` must be exported for every account, not just `PATH`.** Plugin *execution* needs
  only `PATH`, but every `kubectl krew` subcommand resolves its root from `KREW_ROOT` and falls
  back to `$HOME/.krew`. So `/etc/profile.d/krew.sh` sets both.
- **Getting that wrong is not merely inert.** With `KREW_ROOT` unset, `kubectl krew list`
  creates an empty `~/.krew/{bin,index,receipts,store}` skeleton in the caller's home and *then*
  fails with "krew local plugin index is not initialized". Every account that types
  `kubectl krew` once would acquire a stray directory — which is also the mechanism behind the
  `~/.krew` follow-up below.
- **Size and mode.** A root with the three plugins is ~23 MB, of which ~9 MB is the krew-index
  git clone. `u=rwX,go=rX` throughout per policy point 4; the index is a git working tree, so
  check that `git` does not object to a world-readable clone owned by another user
  (`safe.directory` affects `git` run *by* another user, and krew shells out to `git` only on
  refresh — a root-only path — but confirm it at write time rather than assume).

Three options:

- (a) **Recommended.** Shared root at `/usr/local/krew`, installed and updated as root, with the
  plugin set as a play var (`krew_plugins: [ctx, ns, node-shell]` — the three the current README
  tells users to install by hand) so the curated set is version-controlled rather than folklore.
  `KREW_ROOT` and `PATH` via `/etc/profile.d/krew.sh`, install tree at `u=rwX,go=rX` per policy
  point 4, smoke test `kubectl krew list` and `kubectl krew version` as uid 65534 against the
  shared root. The README documents the escape hatch: an account wanting its own plugin set
  exports `KREW_ROOT=$HOME/.krew` in its own `~/.bashrc` — which runs after `/etc/profile.d`,
  so it wins — and runs krew's installer for itself.
- (b) Move it to `_personal/container/krew.yml` with an explicit `target_users` list, the same
  treatment `_personal/ai-agent/` gets. Honest about what krew is, but it means every account's
  plugins are managed by a playbook run, and it puts a *tool* in the tree reserved for
  identities.
- (c) Drop krew and install the three plugins as plain binaries in `/usr/local/bin`
  (`kubectl-ctx`, `kubectl-ns`, `kubectl-node_shell` are exactly what kubectl's plugin
  discovery looks for — no plugin manager is required to have plugins). Fewest moving parts,
  and it forfeits `krew search`/`krew upgrade` entirely.

(a) and (c) are both defensible; (a) is recommended because it keeps the tool the README already
documents. Note that whichever is chosen, the `~/.krew` trees already on provisioned hosts stay
(this host has one, with all three plugins) — see [Known follow-ups](#known-follow-ups).

**`docker.yml` (#3) — the default that will look like a regression.** Covered by
[B1](#policy-amendments); it is listed here because it is the single change in this migration
most likely to be reverted by someone who does not know why it is there. State it three times —
in the playbook header comment, in the README section, and in the run summary the playbook
prints when `docker_users` is empty:

```text
Docker is installed and running. No account was granted access to the socket.
Membership of the `docker` group is equivalent to passwordless root on this host.
Grant it deliberately, per account:
  ansible-playbook container/docker.yml -e host=<host> -e docker_users=alice,bob
```

Also decide, at write time, whether `docker_users` accepts a comma-separated string (matching
`_personal/`'s `target_users`) or a YAML list. Match `_personal/` — the same operator types
both.

## Order of work

Four waves, each ending in a commit and a status-table update:

1. **Decisions first (no playbooks).** The kubectl collision (#4), krew's shape (#8), the Helm
   3→4 pin (#5), and the `xhost` question (B5). MIGRATION2's wave 1 tried this and only managed
   one of three up front; the reason it cost nothing was that both late decisions resolved
   *towards doing less*. Two of these four do not have that property — the kubectl choice and
   the krew choice each add a file (a preferences pin, a shared root) and are referenced by the
   playbooks that follow — so settle them before writing, not during.
2. **The two that are almost right — #1, #2.** `devcontainers.yml` and `podman.yml` are apt and
   npm, no vendor repository, no root-equivalent grant. Pure correctness work: pins,
   version-aware guards, unprivileged verification. They establish the house style for this
   directory (in particular the B4 verification shapes) at the lowest risk.
3. **Docker and the k8s clients — #3, #4, #5.** `docker.yml` first: #6 and #7's smoke tests are
   written against a host where the daemon exists, and B1's grant default is easier to reason
   about before the tools that depend on it. Then `kubectl.yml` (which needs wave 1's collision
   decision) and `helm.yml` (which needs the version decision).
4. **The cluster tools and the plugin manager — #6, #7, #8.** `kind` and `minikube` are
   independent of each other and both depend on #3 only for their documented prerequisite, not
   for their install. `krew` goes last: it depends on wave 1's shape decision and on `kubectl`
   being the one this repo installs.

## Procedure

MIGRATION.md's [ten-step procedure](MIGRATION.md#procedure) and MIGRATION2's
[three additions](MIGRATION2.md#procedure) apply unchanged, with three more:

- **After step 1 (read the source playbook),** fill in that tool's row of the [per-tool state
  table](#per-tool-state-grants-and-shared-config) and confirm the migrated playbook touches
  nothing in the per-user column and grants nothing outside an explicit list.
- **Before step 6 (write the playbook),** run the B5 check — `apt-cache policy` *and*
  `apt-cache madison` for the package name, on the target, with every repository this repo adds
  already configured. A5's "does another playbook add this repository" is not the same question
  as "does another repository publish this package", and only the second one would have caught
  `kubectl`.
- **In step 10 (run it),** run it twice. The second run must report `changed=0`. Five of the
  eight source playbooks cannot upgrade what they installed and the sixth re-downloads its
  keyring every run; both defects are invisible in a first run and obvious in a second. Then
  bump the pin with `-e` and confirm the version actually moves — that is the direct test of
  policy point 6, and it is what the `stat.exists` guards fail.

## Migration status

| Source playbook | Old mechanism | Target mechanism | Pinned | Status |
| --- | --- | --- | --- | --- |
| `devcontainers.yml` | `npm install -g @latest` | npm global, pinned, prefix from run time | TBD | Not started |
| `podman.yml` | apt, unpinned | apt, pinned; linger by explicit list | TBD | Not started |
| `docker.yml` | vendor apt repo, unpinned | vendor apt repo, A5 cleanup, pinned; group by explicit list | TBD | Not started |
| `kubectl.yml` | `pkgs.k8s.io` v1.30, unpinned | decision (a)/(b)/(c) — see note | TBD | Not started |
| `helm.yml` | vendor apt repo, unpinned | vendor apt repo, A5 cleanup, pinned (3→4) | TBD | Not started |
| `kind.yml` | release binary, `stat.exists` | release binary + checksum + version guard | TBD | Not started |
| `minikube.yml` | release binary, `stat.exists` | release binary + checksum + version guard | TBD | Not started |
| `krew.yml` | `curl \| sh` → `~/.krew` | decision (a)/(b)/(c) — see note | TBD | Not started |

The `Pinned` column stays `TBD` until each playbook is written. This is deliberate and is the
same call MIGRATION2 made: MIGRATION.md's step 3 requires checking upstream at write time, and
the [survey below](#upstream-survey-2026-08-11) is stale the day after it was taken.

**Effect on the repo's classification when this is done.** The [multi-user support
status](README.md#multi-user-support-status) table currently counts `container/` as six of the
eight *mixed* rows (`docker`, `podman`, `kubectl`, `helm`, `kind`, `minikube`), one of the six
*personal only* rows (`krew`), and one of the four *effectively shared* rows (`devcontainers`).
Completing this migration empties three quarters of the mixed category and leaves it as
`core/mise.yml` and `core/samba.yml` alone — which is the point at which "the legacy tree" means
`core/` plus one VS Code playbook, and the underscore on `_multi-user/` starts to look like it
has outlived its purpose.

## Upstream survey (2026-08-11)

Checked while writing this plan, to confirm each target mechanism exists. **Every version here
must be re-checked at write time, and every apt candidate re-checked against the target host.**
These readings come from `localhost`, which already carries the Docker, Kubernetes, Google Cloud
SDK, HashiCorp, NodeSource and mise repositories and is therefore not a clean read of what a
fresh `ws01`/`ws02` sees.

| Tool | Finding |
| --- | --- |
| `kubectl` | `pkgs.k8s.io/core:/stable:/v1.36` carries `1.36.3-1.1` (`dl.k8s.io/release/stable.txt` → `v1.36.3`). Colliding Google package `1:579.0.0-0`; see [#4's note](#notes-on-the-four-that-need-a-decision). `dl.k8s.io/release/v1.36.3/bin/linux/amd64/kubectl` returns 200 with a `.sha256` sibling, if (b) is ever chosen. |
| `helm` | Vendor repo candidate `4.2.3-1`; 3.x line still published, latest `3.21.3-1`. No Ubuntu archive candidate at all (`apt-cache policy helm` is empty on resolute), so the vendor repo stays. |
| `kind` | `v0.32.0` (installed here: 0.27.0). Assets `kind-linux-{amd64,arm64}` each with a per-asset `.sha256sum` — one file per asset, not a combined `checksums.txt`. |
| `minikube` | `v1.38.1`. Assets `minikube-linux-<arch>` + `.sha256`, and also `minikube_1.38.1-0_<arch>.deb`. The `.deb` is tempting and rejected: there is no repository behind it, so it is a `dpkg -i` with no upgrade path, and the raw binary keeps `kind.yml` and `minikube.yml` the same shape. |
| `minikube` env | `cmd/minikube/cmd/root.go` calls `viper.SetEnvPrefix(...)` + `viper.AutomaticEnv()`, and its own comment states "viper maps `$MINIKUBE_ROOTLESS` to `rootless` property automatically" — so `MINIKUBE_DRIVER` → `driver` is very likely real. **Still verify against the installed binary** per B2 before writing it to `/etc/profile.d`; MIGRATION2 was wrong three times out of eight on exactly this kind of inference. |
| `krew` | `v0.5.0`. Assets `krew-linux_<arch>.tar.gz` each with a `.tar.gz.sha256` sibling. `releases/latest` (what the source playbook uses) resolves to it. A shared root was rehearsed at this version — see the [table in #8's note](#notes-on-the-four-that-need-a-decision) for what does and does not work read-only. |
| `docker` | `download.docker.com/linux/ubuntu resolute/stable` publishes for this release directly — no codename map needed, unlike Microsoft's and HashiCorp's repos. Installed `5:29.5.0-1~ubuntu.26.04~resolute`, candidate `5:29.7.2-1~ubuntu.26.04~resolute`. Note the pin string embeds the release codename, so it is not portable across Ubuntu versions the way `2.97.0` is. |
| `podman` | Ubuntu `resolute` carries `5.7.0+ds2-3build1` and `podman-compose 1.5.0-2`; both are current enough that apt stays. Installed here already. |
| `devcontainers` | npm `@devcontainers/cli` latest `0.88.0`; installed here `0.87.0` — the `which devcontainer` guard is why it never moved. npm global prefix on this host is `/usr` (NodeSource), which is the same split MIGRATION.md's `markdownlint` finding describes: read it at run time, never assume. |
| `bash-completion` | Installed (`1:2.16.0-8build1`), and `/etc/bash.bashrc` already carries the `profile.d for interactive shells` block from `_multi-user/tools/modern-cli-tools.yml`. Both B3 destinations work on this host today. |

## Known follow-ups

- **`~/.bashrc` blocks left by the source playbooks.** Deleting a playbook removes nothing, and
  neither does replacing it: `ANSIBLE MANAGED BLOCK: {kubectl,helm,kind,minikube,krew}` and the
  `xhost` lines stay in every account that ran the originals, and they keep sourcing
  completions from whatever binary `PATH` finds. On `localhost` right now there are three
  (`kind`, `kubectl`, `krew`). Whether the migrated playbooks should remove them — a
  `blockinfile` with `state: absent` for each marker, applied to an explicit user list — is a
  decision this plan leaves open. It is the *opposite* of B2 (a playbook writing into an
  account's `$HOME`), which is the argument against; the argument for is that the repo wrote
  them and nothing else will ever take them out. Same class as the Homebrew per-user cleanup
  that MIGRATION2 documented and did not perform.
- **`~/.krew` trees on provisioned hosts.** Independent of which krew option is chosen: an
  existing `~/.krew/bin` on `PATH` shadows a shared root for that account, exactly as
  `brew shellenv` shadowed `/usr/local/bin`. `localhost` has one with `ctx`, `ns` and
  `node-shell` installed. Per-host, per-account cleanup.
- **`docker` group memberships already granted.** B1's empty default does not revoke anything —
  `append: true`, by design. `localhost` has one account in the group today. If a host's
  membership list should be audited rather than merely added to, that is a separate playbook
  and a separate decision.
- **Repo-wide vendor-repo ownership** — carried from
  [MIGRATION2](MIGRATION2.md#known-follow-ups), with two more instances now named:
  `container/docker.yml` writes an auto-named
  `/etc/apt/sources.list.d/download_docker_com_linux_ubuntu.list` (what `apt_repository`
  generates when no `filename:` is given), and `container/kubectl.yml` writes `kubernetes.list`
  for a stream that is EOL. B5 adds the package-name dimension to that cleanup.
- **Bare `ansible_architecture` is deprecated** — carried from
  [MIGRATION2](MIGRATION2.md#known-follow-ups). All eight playbooks here are to be written with
  `ansible_facts['architecture']` from the start, so the outstanding repo-wide pass still has
  only `_multi-user/cloud-cli/aws-cli.yml` and the `_multi-user/tools/` playbooks to touch.
- **Retiring `container/`.** The gate is the same one `tool/` and `cloud-cli/` passed: every
  successor verified against a real host. Note what "verified" has covered so far, because the
  gate has been weaker than it sounds — `cloud-cli/` was retired on `localhost` runs alone,
  under ansible-core 2.20, with no SSH path exercised at all. `ws01`/`ws02` have never been
  provisioned by either generation. This migration is a chance to fix that rather than inherit
  it: run at least one wave-2 playbook from a 24.04 control node over SSH, which is the check
  [MIGRATION2's scope note](MIGRATION2.md#scope) called for and no wave ever performed.
