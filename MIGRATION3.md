# Multi-User Workstation Container Playbook Migration

Policy and procedure for migrating the container and Kubernetes playbooks from `container/` to
`_multi-user/container/`.

**Status: complete.** All seven playbooks are migrated, verified against `localhost`, `ws01`
and `ws02`, and
retired — the originals were deleted on 2026-08-14 and `container/` is gone with them, as
`tool/` and `cloud-cli/` were before it. All
three decisions [wave 1](#order-of-work) called for are settled — the kubectl package collision
as (a), the Helm pin as 4.2.3-1, and the `xhost` question by deleting the line. Wave 2 migrated
`devcontainers.yml` and `podman.yml`; wave 3 migrated `docker.yml`, `kubectl.yml` and
`helm.yml`, including the apt preferences pin that resolves the kubectl collision; wave 4
migrated `kind.yml` and `minikube.yml`. The [retirement gate](#known-follow-ups) was narrower
than the word suggests when it was taken — the same `localhost`-only, ansible-core 2.20-only
evidence `cloud-cli/` was retired on — but the 24.04-control-node-over-SSH run this plan called
for **has since been performed: all seven playbooks run `failed=0` against `ws01` and `ws02`**,
and it found one defect (`helm.yml`) that no `localhost` run could have. See
[Notes on the three that need a decision](#notes-on-the-three-that-need-a-decision),
[Wave 2](#wave-2-devcontainers-podman), [Wave 3](#wave-3-docker-kubectl-helm),
[Wave 4](#wave-4-kind-minikube),
[the `ws01`/`ws02` run](#the-ws01ws02-run-2026-08-17--and-the-one-defect-only-a-216-control-node-could-find)
and [Migration status](#migration-status).

`container/krew.yml` was the eighth. It is not in this plan: it was
[retired](README.md#retired-containerkrewyml) on 2026-08-14 rather than migrated, because krew
is per-user by design and a shared root is the shape this repo spent two migrations removing.
See [Scope](#scope).

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
the one where the multi-user question is least about *reach*. Six of its seven playbooks already
put the binary somewhere every account can execute it — apt packages and `/usr/local/bin` — and
the seventh (`devcontainers.yml`) installs into a root-owned npm prefix. What they get wrong is
everything around the binary. The one playbook whose reach was genuinely the problem, `krew.yml`,
is [retired](README.md#retired-containerkrewyml) rather than migrated.

MIGRATION.md's three causes and MIGRATION2's two recur, and three more are new:

1. **Homebrew ownership.** Does not apply. No playbook here uses `brew`, and
   [`core/homebrew.yml` is retired](README.md#retired-corehomebrewyml).
2. **Per-user shell profiles.** The dominant cause here. Four playbooks
   (`kubectl`, `helm`, `kind`, `minikube`) write a `blockinfile` to
   `/home/{{ <tool>_user }}/.bashrc`, and two more (`docker`, `podman`) `lineinfile` an
   `xhost` call into `~/.bashrc`. Six of seven, more than either previous directory.
3. **Per-user install prefixes.** No longer applies. `krew.yml` was the only case — installed
   into `~/.krew`, with `$HOME/.krew/bin` prepended to `PATH` — and that is krew's designed
   shape rather than a defect in the playbook, which is why it was
   [retired](README.md#retired-containerkrewyml) instead of migrated. The one prefix still worth
   care is npm's, which `devcontainers.yml` inherits from the system Node: read it at run time,
   never assume it (MIGRATION.md's `markdownlint` finding).
4. **Install-time `lookup('env', ...)` baked into shared state** (MIGRATION2 cause 4). Six of
   seven playbooks open with `<tool>_user: "{{ lookup('env', 'USER') }}"`. Nothing renders it
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
   image), `~/.docker/`. Unlike a credential file, this state appears the first time an account
   *uses* the tool, and it is correct that it is per-user. The rule that follows is a
   prohibition, not a task: a migrated playbook must not pre-create it, must not share it, and
   must not write one account's copy on behalf of another. `minikube.yml` task 6
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
never again. Not one of the seven pins a version, and four of seven cannot upgrade what they
installed — the three guarded ones plus `kubectl.yml`, whose apt stream is EOL.

## Scope

| | |
| --- | --- |
| Source | `container/*.yml` (7 playbooks) + `container/README.md` — the whole directory, now retired |
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

- **krew.** `container/krew.yml` is [retired](README.md#retired-containerkrewyml) (2026-08-14),
  not migrated, and there will be no `_multi-user/container/krew.yml`. A plugin manager whose
  root is writable by exactly one account is the Homebrew shape again: a shared
  `KREW_ROOT=/usr/local/krew` lets every account *run* the plugins root installed and lets none
  of them add one. kubectl finds plugins on `PATH` with no manager involved, so the three
  plugins the README recommended (`ctx`, `ns`, `node-shell`) can be plain binaries in
  `/usr/local/bin` if they are wanted back — see the retirement note for the full argument and
  for what the shared-root rehearsal established.
- `core/` — all that remains of the legacy tree after this migration, and a harder problem than
  any of the three tool directories: `agent-base.yml` and `x11vnc.yml` are desktop-session and
  VNC setup, which is per-identity in a way no relocation fixes. `gui-tools/` was the other
  survivor until 2026-08-14, when it was [retired](README.md#retired-gui-tools) with its one
  VS Code playbook.
- ~~`container/*` itself stays in place until its successors are verified, the same way `tool/`
  and `cloud-cli/` did. Retiring it is the last step, not the first.~~ **Retired 2026-08-14.**
  All seven originals and the directory's README were deleted once every successor was
  verified, and `container/` no longer exists. What "verified" covers is narrower than the
  word suggests — see the [follow-up](#known-follow-ups) — and the originals are recoverable
  from git history (`git log --diff-filter=D -- container/`).
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
`~/.docker`. `minikube config set driver docker` is the case in hand: it writes
`~/.minikube/config/config.json` for whoever ran the playbook and nobody else, so the
"default driver" it sets is a default for exactly one account.

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
   `devcontainer --help`.
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
and reports success. See [#3's note](#notes-on-the-three-that-need-a-decision).

The `xhost` question belonged here too, as the one input this plan deliberately left open:
**establish what `xhost +local:docker` grants before deciding what replaces it.** The `local`
family's name field may be ignored, in which case the line is equivalent to `xhost +local:` and
grants every local connection — a much wider grant than its name suggests — or it may add a
host entry that matches nothing and grant nothing at all.

> **Decided 2026-08-14: the `xhost` line is deleted, and nothing replaces it.** Neither
> `docker.yml` nor `podman.yml` gets an `xhost` task, a `/etc/profile.d` equivalent, or the
> `-e` flag this section previously floated.
>
> The decision does not depend on which way the semantics fall, which is why it could be taken
> without the measurement. Both branches end outside `~/.bashrc`: if the name is ignored the
> line silently grants every local connection to the X server, which is a security decision a
> container-runtime installer has no business making on six accounts' behalf; if the name
> matches nothing the line is dead code that has been running in every interactive shell for
> its whole life. There is no third branch in which appending it to `.bashrc` is correct.
>
> **The measurement was attempted and is not recorded, because it failed.** A private `Xvfb`
> with a real auth cookie was used to compare `+local:docker`, `+local:nosuchthing` and bare
> `+local:` against an uncredentialed client. The run is void: `/tmp/.X11-unix` on this host is
> owned by `gdm-greeter` rather than `root`, the test server's unix listener never bound, and
> the contradiction shows plainly in the transcript — `xhost +` reported "access control
> disabled" while the next listing still reported it enabled and every probe still refused, so
> the probes and the `xhost` calls were not reaching one consistent server. The one thing it
> did establish is client-side only and settles nothing about the server: `xhost` prints an
> identical message for all three spellings, so the name never reaches the server as a
> distinguishing value. Anyone re-running this needs a host whose `/tmp/.X11-unix` is
> `root:root` mode `1777`, or an `Xvfb -displayfd` on a private `XDG_RUNTIME_DIR`.
>
> **Consequence to document, not to solve.** Deleting the line costs the one thing it was for:
> a containerised GUI app can no longer reach the host X server just because the account once
> ran the playbook. An account that wants that runs `xhost` itself, per session, deliberately.
> `docker.yml`'s and `podman.yml`'s README sections must say so — it is a smaller regression
> than [B1](#policy-amendments)'s, but it is the same shape, and the same person will hit it.

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
| `minikube` | `~/.minikube/` — certs, profiles, kicbase image | needs `docker` group to do anything | `/etc/bash_completion.d/minikube` only — `MINIKUBE_DRIVER` verified as read, then [rejected](#wave-4-kind-minikube) |
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

### Notes on the three that need a decision

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

> **Decided 2026-08-14: (a).** Keep apt and pkgs.k8s.io, bump the stream to `v1.36`, pin
> `1.36.3-1.1`, and write `/etc/apt/preferences.d/kubectl` pinning the pkgs.k8s.io origin at
> priority `1001`. Re-verified on `localhost` the day the decision was taken:
>
> ```console
> $ apt-cache policy kubectl
>   Installed: 1:568.0.0-0
>   Candidate: 1:580.0.0-0
> $ curl -sSL https://dl.k8s.io/release/stable.txt
> v1.36.3
> ```
>
> **The candidate moved from `1:579.0.0-0` to `1:580.0.0-0` in the three days between writing
> this plan and deciding it, which is the argument for (a) rather than a detail.** The epoch
> side of the collision is not a fixed obstacle to be stepped over once — it is a stream that
> republishes faster than this repo will ever re-run its playbooks, and every one of those
> publications outranks every version pkgs.k8s.io will ever carry. Only a preferences pin
> survives that; `--allow-downgrades` at install time does not, because the next unrelated
> `apt upgrade` on the host silently takes `kubectl` back.
>
> Two mechanics for write time. The `v1.36` stream carries exactly one version, `1.36.3-1.1`
> (confirmed against the flat repo's own `Packages` index, which needs `curl -L` — pkgs.k8s.io
> 302-redirects), so the pin is exact rather than a floor, and it will need bumping in step with
> upstream patch releases. **There is no `v1.37` stream yet** — `core:/stable:/v1.37` returns no
> index — so the "editing the URI" note above is a future task, not a choice available now.
>
> (b) and (c) are both declined for the reasons already given: (b) shadows Google's
> `/usr/bin/kubectl` by `PATH` order instead of resolving the conflict, recreating the exact
> Homebrew precedence problem this repo has been carrying since MIGRATION.md, and (c) makes the
> Kubernetes client version a function of Cloud SDK releases.

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

> **Decided 2026-08-14: 4.2.3-1**, with `-e helm_version=3.21.3-1` as the documented fallback.
> Both figures re-verified against the vendor repository's own `Packages` index on the day of
> the decision — 16 versions published, `3.13.3-1` through `4.2.3-1`, with `3.21.3-1` the
> newest of the 3.x line and `4.2.0-1`/`4.2.3-1` the only 4.x entries. The repository serves
> exactly one package name (`helm`), so the major version is carried entirely by the pin.
>
> The in-repo consumer check was re-run and still finds nothing, and `apt-cache policy helm` on
> `localhost` is still empty — the Buildkite repository is not configured on this host, so
> unlike `kubectl` there is no incumbent to displace and no collision to resolve. That also
> means the figures above come from the vendor index over HTTP rather than from apt, and that
> **this pin has never been resolved by apt on any host in this repo**; treat the first run as
> the check that the version string is spelled the way apt expects.
>
> This is the one decision in wave 1 that changes what the repo installs rather than how, so it
> is stated as a 3→4 change in the README, in the playbook header, and in the commit message —
> three places, the same discipline [B1](#policy-amendments) gets, and for the same reason: a
> reader who assumes continuity with the source playbook will be wrong.

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

1. **Decisions first (no playbooks). Done — all three, up front.** The kubectl collision (#4)
   resolved as (a), the Helm 3→4 pin (#5) as `4.2.3-1`, and the `xhost` question (B5) by
   deleting the line. A fourth decision — krew's shape — was settled ahead of this plan
   by [retiring it](README.md#retired-containerkrewyml). MIGRATION2's wave 1 tried this and only
   managed one of three up front; the reason it cost nothing was that both late decisions
   resolved *towards doing less*. One of these three does not have that property — the kubectl
   choice adds a file (a preferences pin) that the playbooks after it reference — so settle it
   before writing, not during. That is what happened, and it is the first wave 1 in the series
   to close before any playbook was written.

   Two of the three resolved *towards doing less* anyway (delete the `xhost` line; keep the
   apt mechanism kubectl already had), and the third is a version string. So no playbook
   written in later waves is owed a revisit — but `kubectl.yml` now owes a file that no
   playbook in either previous migration produced, an `/etc/apt/preferences.d/` entry, and
   wave 3 is where that gets designed.
2. **The two that are almost right — #1, #2. Done.** `devcontainers.yml` and `podman.yml` are
   apt and npm, no vendor repository, no root-equivalent grant. Pure correctness work: pins,
   version-aware guards, unprivileged verification. They establish the house style for this
   directory (in particular the B4 verification shapes) at the lowest risk. Both verified
   against `localhost` — see [Wave 2](#wave-2-devcontainers-podman).
3. **Docker and the k8s clients — #3, #4, #5. Done.** `docker.yml` first: #6 and #7's smoke tests are
   written against a host where the daemon exists, and B1's grant default is easier to reason
   about before the tools that depend on it. Then `kubectl.yml` (which needs wave 1's collision
   decision) and `helm.yml` (which needs the version decision).
4. **The cluster tools — #6, #7. Done.** `kind` and `minikube` are independent of each other and both
   depend on #3 only for their documented prerequisite, not for their install. They go last
   because their smoke tests are the weakest in the directory (`--version` alone, per B4), so
   nothing else should be waiting on them.

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
- **In step 10 (run it),** run it twice. The second run must report `changed=0`. Four of the
  seven source playbooks cannot upgrade what they installed and a fifth (`docker.yml`)
  re-downloads its keyring every run; both defects are invisible in a first run and obvious in
  a second. Then
  bump the pin with `-e` and confirm the version actually moves — that is the direct test of
  policy point 6, and it is what the `stat.exists` guards fail.

## Migration status

| Source playbook | Old mechanism | Target mechanism | Pinned | Status |
| --- | --- | --- | --- | --- |
| `devcontainers.yml` | `npm install -g @latest` | npm global, pinned, prefix from run time | 0.88.0 | Verified (localhost, ws01, ws02) |
| `podman.yml` | apt, unpinned | apt, pinned; linger by explicit list | podman 5.7.0+ds2-3build1, podman-compose 1.5.0-2 | Verified (localhost, ws01, ws02) |
| `docker.yml` | vendor apt repo, unpinned | vendor apt repo, A5 cleanup, pinned; group by explicit list | docker-ce 5:29.7.2-1~ubuntu.26.04~resolute, containerd.io 2.3.3, buildx 0.36.1, compose 5.4.0 | Verified (localhost, ws01, ws02) |
| `kubectl.yml` | `pkgs.k8s.io` v1.30, unpinned | `pkgs.k8s.io` v1.36 + `/etc/apt/preferences.d/kubectl` — decision (a) | 1.36.3-1.1 | Verified (localhost, ws01, ws02) |
| `helm.yml` | vendor apt repo, unpinned | vendor apt repo, A5 cleanup, pinned (3→4) | 4.2.3-1 | Verified (localhost, ws01, ws02) |
| `kind.yml` | release binary, `stat.exists` | release binary + checksum + version guard | 0.32.0 (was 0.27.0) | Verified (localhost, ws01, ws02) |
| `minikube.yml` | release binary, `stat.exists` | release binary + checksum + version guard | 1.38.1 | Verified (localhost, ws01, ws02) |
| `krew.yml` | `curl \| sh` → `~/.krew` | — | — | [Retired](README.md#retired-containerkrewyml) 2026-08-14, not migrated |

Every row is also **retired**: none of the source playbooks named in the first column still
exists, each having been deleted on 2026-08-14 once its successor was verified, and
`container/` was removed with the last of them. The column is kept because it is what each
migrated playbook is a successor *to*, and every playbook's header comment still refers to it
by name — as do the tasks that clean up after it, which are the one part of this migration
that outlives the source: `docker.yml`, `kubectl.yml` and `helm.yml` each remove apt sources
and keyrings their predecessor wrote, on hosts where the predecessor ran.
`git log --diff-filter=D -- container/` recovers any of them.

The `Pinned` column stays `TBD` until each playbook is written. This is deliberate and is the
same call MIGRATION2 made: MIGRATION.md's step 3 requires checking upstream at write time, and
the [survey below](#upstream-survey-2026-08-11) is stale the day after it was taken.

Wave 1 decided two version strings without filling the column in, which is not a contradiction:
`kubectl` at `1.36.3-1.1` and `helm` at `4.2.3-1` are decisions about *which* version this repo
installs, and they were needed before writing because a preferences pin and a major-version bump
both change what the playbook has to do. The column records what a written playbook actually
pins, re-checked at write time — and the `kubectl` epoch moving twice in three days is the
reason those are two different questions.

**Effect on the repo's classification, now that this is done.** The [multi-user support
status](README.md#multi-user-support-status) table counted `container/` as six of the
eight *mixed* rows (`docker`, `podman`, `kubectl`, `helm`, `kind`, `minikube`) and one of the
three *effectively shared* rows (`devcontainers`) — its seven playbooks, in full. The eighth,
`krew.yml`, was one of the *personal only* rows until it was retired, which already took that
category from six to five. Retiring the directory moved all seven at once: *multi-user* 24 →
31, *effectively shared* 3 → 2, *mixed* 8 → 2, leaving that category as `core/mise.yml` and
`core/samba.yml` alone. The total is unchanged at 40, because seven successors replaced
exactly seven originals. "The legacy tree" now means `core/` and nothing else, six playbooks
of the forty, now that [`gui-tools/` is retired](README.md#retired-gui-tools) too — and the
underscore on `_multi-user/` has outlived the purpose
[MIGRATION.md gave it](MIGRATION.md#scope), which was to sort a staging tree apart from live
directories that no longer exist. Renaming it is a [follow-up](#known-follow-ups), not a
loose end in this migration.

### Wave 2 (`devcontainers`, `podman`)

Both verified against `localhost`, `failed=0`, with the same caveats as everything else in
`_multi-user/`: ansible-core 2.20 only, and a local connection exercises neither the 24.04
control node nor the SSH path. Re-runs are idempotent — `ok=12 changed=2` for
`devcontainers.yml` and `ok=14 changed=2` for `podman.yml`, every `changed` being the scratch
`HOME` created and removed. `--check` was exercised first on both and wrote nothing. Post-run
checks independent of the playbooks: `devcontainer 0.88.0` root-owned and world-readable under
`/usr/lib/node_modules/@devcontainers/cli`, `podman 5.7.0` / `podman-compose 1.5.0`, and
`/var/tmp` holds no leftovers.

The procedure's "run it twice, then bump the pin with `-e`" step was carried out in full on
`devcontainers.yml`: pinning `0.87.0` moved the install *backwards* and the guard reported the
change, which is the direct test policy point 6 exists for and precisely what the source
playbook's `which devcontainer` guard could never do. `podman.yml` cannot be tested that way —
Ubuntu's archive publishes exactly one candidate for both packages — so the equivalent check was
a deliberately wrong pin (`-e podman_version=9.9.9-1`), which fails loudly at the install task
and changes nothing, rather than silently installing whatever apt preferred.

**A tool that looks offline is not offline: `devcontainer read-configuration` calls `docker
ps`.** This was going to be the playbook's B4 level-1 verification — parsing a real
`devcontainer.json` is exactly the "offline real work" the policy prefers — and it failed as uid
65534 while succeeding as root on the same directory and the same file. The cause is not
permissions: the CLI shells out to
`docker ps -q -a --filter label=devcontainer.local_folder=...` to find an existing container for
the workspace folder, so it fails for any account outside the `docker` group. It exits 1 having
printed only its startup banner; the `docker ps` call is visible **only** under
`--log-level trace`. Two things follow. First, this playbook's check is B4 level 2
(`devcontainer --help`), which is what [the plan](#per-tool-migration-plan) suggested anyway —
there is no subcommand that does real devcontainer work without a runtime. Second, the
[per-tool table](#per-tool-state-grants-and-shared-config)'s `devcontainer` row understates the
dependency: it is not merely that `devcontainer up` needs Docker, it is that everything except
`--help` and `--version` does. On a host where `docker_users` is empty — B1's default — the Dev
Containers CLI is installed for everyone and usable by no one.

**podman reads `$HOME` before it will even report its version.** `podman --version` as uid 65534
fails with `stat /root/.config: permission denied`, because `setpriv` does not change `HOME` and
podman stats `$HOME/.config` before doing anything at all. MIGRATION2's A4 already called for a
writable scratch `HOME`, but for tools that were doing real work; this is the weakest possible
subcommand needing one, so the rule to carry into waves 3 and 4 is to give *every* smoke test in
this directory a scratch `HOME` by default rather than adding one when a check fails. It is the
same class of finding as MIGRATION2's `gcx` cwd defect — a correct install failing its own
verification on the connecting account's environment.

**The subuid assertion earns its place, and its ordering matters.** Run with
`-e podman_linger_users=nobody`, the playbook fails at task 10 with the `usermod --add-subuids`
remedy and grants nothing, because the assertion sits ahead of the `enable-linger` task. An
account that cannot run rootless podman does not get lingering enabled for it as a consolation
prize. Run with an account that has a range and already lingers, the grant tasks report `ok` and
`skipping` rather than `changed`, which is the idempotency the source playbook's
`changed_when: false` only pretended to have.

### Wave 3 (`docker`, `kubectl`, `helm`)

All three verified against `localhost`, `failed=0`, with the same caveats as everything else in
`_multi-user/`: ansible-core 2.20 only, and no SSH path. Re-runs are idempotent — `ok=18
changed=2` for `docker.yml`, `ok=19 changed=2` for `kubectl.yml`, `ok=18 changed=3` for
`helm.yml` — every `changed` being scratch state created and removed. `--check` was exercised
first on all three. Post-run checks independent of the playbooks: `docker 29.7.2` with
`buildx 0.36.1` / `compose 5.4.0` and `containerd 2.3.3`, `kubectl v1.36.3`, `helm v4.2.3`;
`apt-get update` warns about nothing; `/var/tmp` holds no leftovers.

**Decision (a) works, and the pin is what does the work.** After the run `apt-cache policy
kubectl` reports candidate `1.36.3-1.1` even though `1:580.0.0-0` is still visible in the
version table, `kubectl version --client` prints `v1.36.3` with no `-dispatcher` suffix, and
`apt-get -s upgrade` proposes no change to the package. That last check is the one worth keeping
as a task: it is the difference between "the right version is installed today" and "the right
version survives the next `apt upgrade`", and `kubectl.yml` task 12 asserts it on every run
rather than trusting the install.

**The two A5 key forms are not interchangeable, and this is the sharp edge.**
`deb822_repository` given an **inline** armored key writes no keyring at all — it embeds the
block in the `.sources` file's `Signed-By:` field — and returns `key_filename` **empty rather
than undefined**, so `| default('/etc/apt/keyrings/<name>.asc')` does *not* fire (Jinja's
`default()` only substitutes undefined values unless given `true` as its second argument). The
first run of `docker.yml` failed on exactly this: gpg was invoked with an empty path and the
fingerprint assertion reported the key missing, on a host where the key was perfectly correct.
Given a **URL**, the module does download a keyring and does return `key_filename` — which is
why `cloud-cli/github-cli.yml` and `kubectl.yml` can inspect the file and `docker.yml` and
`helm.yml` cannot. The fix in the inline case is to assert the *variable's* bytes
(`gpg --show-keys` with `stdin:`), which is the more meaningful check anyway: it verifies what
this repo pins, and apt verifies the other direction for itself.

**Which form to use was decided by expiry, per MIGRATION2's rule, and the three playbooks split
two ways.** Docker's key (`9DC85822…`) and the Helm repository's packagecloud key
(`DDF78C3E…`) carry no expiry, so their bytes are pinned inline. The Kubernetes stream key
(`DE15B144…`) **expires 2026-12-29**, so `kubectl.yml` fetches it by URL each run and pins only
the fingerprint. One difference from `github-cli.yml` is worth recording: there, an assertion
against the *non-expiring successor* key survives the rotation. pkgs.k8s.io publishes no
successor to assert, so when that key rotates `kubectl.yml` will fail at task 5 rather than
follow a new key silently. That is the intended behaviour, and the failure message says so.

**B3's destination was verified end to end, not assumed — and the first probe of it was wrong.**
`/etc/bash_completion.d` is read on this host because `bash-completion`'s own
`/etc/profile.d/bash_completion.sh` sources `/usr/share/bash-completion/bash_completion`, which
lists `/etc/bash_completion.d` among its compat directories. An initial check suggested
completions were *not* being loaded; that was a bad probe (it looked for `__start_gcloud`, a
function the gcloud completion file does not define — it defines `_python_argcomplete`, and the
vault file uses `complete -C` with no function at all). Both `kubectl.yml` and `helm.yml` now
close with a task that starts a *non-login interactive shell as uid 65534* and asserts the
completion is registered, so the claim is tested on every run rather than inferred from the
existence of a file. The `k` alias needs the `/etc/bash.bashrc` bootstrap as well, and sources
the completion file defensively rather than assuming profile.d runs after the compat directory.

**Docker's negative assertion is the check this directory exists for.** As uid 65534,
`docker ps` fails with `permission denied while trying to connect to the docker API at
unix:///var/run/docker.sock` — matched as *text*, because a non-zero exit alone would also be
produced by a daemon that simply is not running, which would make the assertion pass while
proving nothing. Run with `docker_users` empty on a host where an account was already a member,
the group was left exactly as it was: the empty default granted nothing and revoked nothing,
which is B1's additive rule holding in practice rather than in principle.

**`docker-ce-rootless-extras` is installed but not configured.** B1 requires the README to name
the alternatives to a root-equivalent grant, and an alternative that is documented but absent
from the host is not much of one. Installing the package costs nothing and leaves the per-account
`dockerd-rootless-setuptool.sh install` to each account, which is where B2 says it belongs.

### Wave 4 (`kind`, `minikube`)

Both verified against `localhost`, `failed=0`, re-running idempotently at `ok=12 changed=2` —
the two `changed` being the scratch `HOME` created and removed. `--check` was exercised first on
both and is unusually useful here: the checksum fetch carries `check_mode: false`, so a dry run
validates the version pin against the published checksum upstream without downloading the
binary. Post-run: `kind v0.32.0`, `minikube v1.38.1`, both root-owned mode 0755 in
`/usr/local/bin`, both completions loaded in a non-login interactive shell as uid 65534.

**The `stat.exists` defect was not theoretical.** `kind` moved 0.27.0 → 0.32.0 on the first run
of the migrated playbook — five releases the source playbook could have installed at any point
in the last year and never did, because its guard asked whether the file existed rather than
which version it was.

**Two checksum formats, one asset apiece.** Neither tool publishes a combined `checksums.txt`,
so there is nothing to search — but the two files are not the same shape: kind's
`kind-linux-<arch>.sha256sum` is `<hash>  <filename>` and needs the first field, while
minikube's `minikube-linux-<arch>.sha256` is a **bare hash with no filename at all**. Both
playbooks assert `^[0-9a-f]{64}$` on the result before it reaches `get_url`, so a 404 page or a
redirect fails with a message about the version pin rather than as a checksum that merely never
matches.

**`MINIKUBE_DRIVER` is read — and is still not set.** The [survey](#upstream-survey-2026-08-11)
called this "very likely real" from the viper source and demanded verification; the negative
control settles it, and for once the inference was right:

```console
$ HOME=$scratch MINIKUBE_DRIVER=bogusdriver minikube start --dry-run
  - MINIKUBE_DRIVER=bogusdriver
X Exiting due to DRV_UNSUPPORTED_OS: The driver 'bogusdriver' is not supported on linux/amd64
$ HOME=$scratch MINIKUBE_DRVER=bogusdriver minikube start --dry-run     # near-miss name
  - MINIKUBE_DRVER=bogusdriver
* Automatically selected the docker driver. Other choices: podman, ssh, none
* dry-run validation complete!
```

Being read is necessary, not sufficient (MIGRATION2's rule), and the second line of that output
is the reason a shared default was **rejected**: minikube already auto-selects the docker driver
when Docker is present, so `MINIKUBE_DRIVER=docker` in `/etc/profile.d` would be a no-op on
every account that can use Docker — and a *wrong* default on every account that cannot, since an
account outside `docker_users` would be pushed at the one driver it has no access to instead of
being offered podman. So `minikube.yml` writes no environment variable, and the per-tool table's
conditional row resolves to "completion only". One incidental finding worth keeping: the
variable is invisible to `minikube config get driver`, which reads only the config file, so it
cannot be used to check whether the variable took effect.

**A B2 violation found in this playbook's own first draft, by the check B2 asks for.** Running
`minikube version` — nothing more — creates `$HOME/.minikube`. The playbook invokes minikube
three times as root (the version guard, the post-install verification, and generating the
completion), so every run created `/root/.minikube`. B2 forbids writing under *any* account's
`$HOME` "including the invoker's", and root is an account; the fix is `MINIKUBE_HOME` pointed at
a scratch path on those three tasks, removed by the cleanup task. `kind` was checked for the
same thing and is clean — neither `kind version` nor `kind completion bash` creates state.
The general rule for the next migration: a tool that keeps per-user state may create it on
*any* invocation, including one that only prints a version, so the playbook's own calls need
redirecting as much as the smoke test's do.

### The `ws01`/`ws02` run (2026-08-17) — and the one defect only a 2.16 control node could find

**All seven playbooks run `failed=0` against both real workstations, from a 24.04 control node
(ansible-core 2.16) against Ubuntu 26.04 / Python 3.14 targets.** This discharges, for this
directory, the [retirement-gate follow-up](#known-follow-ups) every "Verified (localhost)" row
carried: the runs exercised the 2.16 floor, a real `remote_user` over SSH, and two hosts that
were provisioned by the *legacy* playbooks rather than being clean. Six of the seven needed no
change. One did.

Final state, both hosts identical, each playbook re-run to idempotency:

| Playbook | Recap (re-run) | Installed |
| --- | --- | --- |
| `devcontainers.yml` | `ok=12 changed=2` | 0.88.0 |
| `podman.yml` | `ok=14 changed=2` | podman 5.7.0, podman-compose 1.5.0 |
| `docker.yml` | `ok=18 changed=2` | docker 29.7.2, buildx 0.36.1, compose 5.4.0, containerd 2.3.3 |
| `kubectl.yml` | `ok=23 changed=2` | kubectl v1.36.3, kubectx/kubens |
| `helm.yml` | `ok=18 changed=3` | helm v4.2.3 |
| `kind.yml` | `ok=12 changed=2` | kind v0.32.0 |
| `minikube.yml` | `ok=12 changed=2` | minikube v1.38.1 |

Every `changed` is scratch state created and removed; `/var/tmp` holds no leftovers on either
host afterwards.

**`helm.yml` failed on both hosts, and neither `localhost` nor 2.20 could ever have caught it.**
Task 14 died writing the smoke chart:

```
An unhandled exception occurred while templating ... template error while templating
string: unexpected '.'. String: apiVersion: v1 ... name: {{ .Release.Name }}-smoke
```

The chart's ConfigMap is Go template source, and it reaches the file through **two** templating
passes: once when the loop item is built, once when `content: "{{ item.content }}"` is expanded.
`{% raw %}` only survives the first. ansible-core **2.20 does not re-template a templated
result**, so the second pass never happened there and the playbook passed; **2.16 does**, and
evaluates Go's `.Release` as Jinja, where a leading dot is a syntax error. The fix is `!unsafe`
on that item's content, which blocks both passes, with the `{% raw %}` markers removed so they
do not leak into the file.

The fix was confirmed on **both** engines, as the [scope](#scope) requires: `failed=0` from the
2.16 control node against both
hosts, and `failed=0` again running the playbook under **ansible-core 2.20.1 on `ws01` itself**
(local connection), where `helm lint` and `helm template` both render the chart. A one-sided fix
here would have been as invisible as the one-sided verification that let the defect through.

This is the exact counterpart to MIGRATION2's `gitlab-cli.yml` finding — one playbook, one
defect, invisible to the verification that was actually run — but it fails on a different axis.
`gitlab-cli.yml` was a *connection-mode* defect (cwd differs local vs remote); this is a
*control-node-version* defect. **The 2.16 floor is not a formality: it is a second
implementation of the template engine, and this repo had a playbook that only worked on one of
them.** Anything writing template syntax through a loop variable is suspect; `misc/gomplate.yml`
was checked and is safe, because its `{% raw %}` blocks sit inline in a `cmd:` string and are
templated once.

**The 2.16 control node otherwise holds, as it did for `cloud-cli/`.** No interpreter complaint
anywhere across seven playbooks and two hosts, so 24.04 stays supported for this directory too.

**The kubectl collision was resolved under harder conditions than `localhost` offered.** Both
hosts had `packages.cloud.google.com` configured (from `cloud-cli/gcloud-cli.yml`) with
candidate `1:580.0.0-0`, and **no kubectl installed at all** — so the preferences pin had to win
the initial candidate selection outright rather than hold a correct version already in place. It
did: `Installed: 1.36.3-1.1`, `Candidate: 1.36.3-1.1`, `kubectl version --client` reporting
`v1.36.3` with no `-dispatcher` suffix, and `apt-get -s upgrade` proposing no change. Decision
(a) is now verified against a live epoch collision on two hosts, which is the case it was chosen
for.

**The predecessor-cleanup tasks fired for real, which `localhost` could only partly show.** Both
hosts still carried the legacy `helm-stable-debian.list` (and helm 4.2.3 installed from it), and
`ws01` still carried `container/docker.yml`'s auto-named
`download_docker_com_linux_ubuntu.list`. Both were removed and replaced by the A5-convention
`.sources` files. The `changed=6` vs `changed=5` split between `ws01` and `ws02` on docker's
first run is precisely that one cleanup task.

**The npm-prefix finding was exercised by two hosts that genuinely disagree.** `ws01` runs
NodeSource node 24 with a global prefix of `/usr`; `ws02` runs the archive's node 22 with
`/usr/local`. `devcontainers.yml` read each at run time and installed to the right place on
both — `/usr/bin/devcontainer` and `/usr/local/bin/devcontainer` respectively. MIGRATION.md's
`markdownlint` finding said never to assume this; until now no run had two hosts that actually
differed.

**B1's additive rule held on a host that had a member.** `ws01` already had one account in the
`docker` group. Run with `docker_users` empty — the default — the group was left exactly as it
was, granting nothing and revoking nothing, while `ws02`'s group stayed empty. B4's subuid
assertion was re-tested over SSH with `-e podman_linger_users=nobody`: it failed at task 10 with
the `usermod --add-subuids` remedy and granted no lingering, the assertion sitting ahead of the
grant as designed.

**A caution for post-run checks, not a defect.** After the run `/root/.minikube` was present on
both hosts, which looks like a [B2](#policy-amendments) violation. It was not the playbook: the
`MINIKUBE_HOME` redirect works, and removing the directory and re-running left it absent. It was
*the verification command* — a bare `minikube version` issued as root to check what got
installed — reproducing wave 4's own finding that any invocation creates the state. The lesson
generalises past minikube: for a tool that keeps per-user state, an ad-hoc check run as root
violates the rule the playbook was careful to keep, and it will be misread as the playbook's
doing.

## Upstream survey (2026-08-11)

Checked while writing this plan, to confirm each target mechanism exists. **Every version here
must be re-checked at write time, and every apt candidate re-checked against the target host.**
These readings come from `localhost`, which already carries the Docker, Kubernetes, Google Cloud
SDK, HashiCorp, NodeSource and mise repositories and is therefore not a clean read of what a
fresh `ws01`/`ws02` sees.

The `kubectl` and `helm` rows were re-checked on 2026-08-14 for wave 1's decisions, and the
table below is left as the 2026-08-11 reading it was taken as. One figure had already moved in
those three days — the colliding Google `kubectl` candidate, `1:579.0.0-0` → `1:580.0.0-0` —
which is exactly the staleness this warning is about. The current readings are in
[#4's](#notes-on-the-three-that-need-a-decision) and #5's decision notes.

| Tool | Finding |
| --- | --- |
| `kubectl` | `pkgs.k8s.io/core:/stable:/v1.36` carries `1.36.3-1.1` (`dl.k8s.io/release/stable.txt` → `v1.36.3`). Colliding Google package `1:579.0.0-0`; see [#4's note](#notes-on-the-three-that-need-a-decision). `dl.k8s.io/release/v1.36.3/bin/linux/amd64/kubectl` returns 200 with a `.sha256` sibling, if (b) is ever chosen. |
| `helm` | Vendor repo candidate `4.2.3-1`; 3.x line still published, latest `3.21.3-1`. No Ubuntu archive candidate at all (`apt-cache policy helm` is empty on resolute), so the vendor repo stays. |
| `kind` | `v0.32.0` (installed here: 0.27.0). Assets `kind-linux-{amd64,arm64}` each with a per-asset `.sha256sum` — one file per asset, not a combined `checksums.txt`. |
| `minikube` | `v1.38.1`. Assets `minikube-linux-<arch>` + `.sha256`, and also `minikube_1.38.1-0_<arch>.deb`. The `.deb` is tempting and rejected: there is no repository behind it, so it is a `dpkg -i` with no upgrade path, and the raw binary keeps `kind.yml` and `minikube.yml` the same shape. |
| `minikube` env | `cmd/minikube/cmd/root.go` calls `viper.SetEnvPrefix(...)` + `viper.AutomaticEnv()`, and its own comment states "viper maps `$MINIKUBE_ROOTLESS` to `rootless` property automatically" — so `MINIKUBE_DRIVER` → `driver` is very likely real. **Still verify against the installed binary** per B2 before writing it to `/etc/profile.d`; MIGRATION2 was wrong three times out of eight on exactly this kind of inference. |
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
  that MIGRATION2 documented and did not perform. The `krew` marker has no successor playbook
  at all now, so for that one the choice is by hand or not at all.

  **Wave 1's `xhost` decision puts the `xhost` lines in that same position.** They are
  `lineinfile` entries rather than marked blocks, so there is not even a marker to match on —
  removing them means matching the literal line — and now that no migrated playbook writes an
  `xhost` line, nothing this repo ships will ever revisit them. On `localhost` there is one,
  `xhost +local:docker` at `~/.bashrc:118`, from `docker.yml`. `podman.yml`'s equivalent is
  absent, which suggests that playbook never ran to completion here — but only suggests it:
  `podman 5.7.0` *is* installed, and lingering *is* enabled for the account, neither of which
  is evidence, because apt could have brought podman in as a dependency and three other
  playbooks in this repo (`core/x11vnc.yml` and two under `_personal/ai-agent/`) also run
  `loginctl enable-linger`. Worth knowing before reading a `podman` run on this host as a
  regression check: its starting state is not a clean one, and it is not knowable which
  playbook produced it. Unlike the completion blocks,
  which are merely redundant once B3 puts the same completions in `/etc`, these keep doing
  whatever they do on every interactive shell, in every account that ran `docker.yml` or
  `podman.yml`. That makes them the strongest candidate in this list for cleanup by hand, and
  the reason to establish the semantics after all — not to decide the migration, which is
  settled, but to know whether the leftovers on existing hosts are inert or are an open X
  server.
- **`~/.krew` trees left by the retired playbook.** Retiring `krew.yml` uninstalls nothing: an
  account that ran it keeps its `~/.krew` tree, its plugins and the `PATH` entry that finds
  them, so krew goes on working there and goes on being invisible to every other account.
  `localhost` has one with `ctx`, `ns` and `node-shell` installed. Per-host, per-account
  cleanup, the same class as the Homebrew and Go/Rust leftovers.
- **`docker` group memberships already granted.** B1's empty default does not revoke anything —
  `append: true`, by design. `localhost` has one account in the group today. If a host's
  membership list should be audited rather than merely added to, that is a separate playbook
  and a separate decision.
- **Repo-wide vendor-repo ownership** — carried from
  [MIGRATION2](MIGRATION2.md#known-follow-ups), with two more instances named here and both now
  closed *in this repo*: `container/docker.yml` wrote an auto-named
  `/etc/apt/sources.list.d/download_docker_com_linux_ubuntu.list` (what `apt_repository`
  generates when no `filename:` is given), and `container/kubectl.yml` wrote `kubernetes.list`
  for a stream that is EOL. Both playbooks are gone, and unlike the earlier closures-by-deletion
  their successors actively clean up after them: `docker.yml`, `kubectl.yml` and `helm.yml` each
  delete their predecessor's source file (and `helm.yml` two generations of keyring) before
  writing their own `.sources`. So a host that runs the successors is cleaned; a host that
  ran only the originals and is never provisioned again keeps them. **Closed 2026-08-16:**
  `core/` — the last directory adding repositories under no shared convention — was
  [retired](MIGRATION4.md#known-follow-ups) the same way, its two vendor-repo playbooks migrated
  to A5-compliant successors that delete the predecessor's source before writing their own. No
  directory left in the repo adds an apt repository outside the shared convention. B5 added the
  package-name dimension to that cleanup while it was still open.
- **Bare `ansible_architecture` is deprecated** — carried from
  [MIGRATION2](MIGRATION2.md#known-follow-ups). All seven playbooks here are to be written with
  `ansible_facts['architecture']` from the start, so the outstanding repo-wide pass still has
  only `_multi-user/cloud-cli/aws-cli.yml` and the `_multi-user/tools/` playbooks to touch.
- ~~**Retiring `container/`.**~~ — **done 2026-08-14.** All seven originals and the directory
  README were deleted, on the gate `tool/` and `cloud-cli/` passed: every successor verified
  against a real host.
- **The retirement gate is weaker than the word "verified" suggests, and this migration
  inherited it rather than fixing it.** Every wave here was verified on `localhost` alone,
  under ansible-core 2.20 alone, with no SSH path and no `remote_user` exercised — exactly the
  evidence `cloud-cli/` was retired on. `ws01`/`ws02` have still never been provisioned by
  either generation. This plan called for fixing it (run at least one wave-2 playbook from a
  24.04 control node over SSH, the check [MIGRATION2's scope
  note](MIGRATION2.md#scope) asked for), **and that run was never performed** — not by wave 2,
  not by any later wave, and not before the deletion. So the item does not close with the
  directory; it moves forward. It applies to all 31 playbooks in `_multi-user/` now, and the
  cheapest way to discharge it is still one playbook, one 24.04 control node, one remote host.

  **Closed for this directory 2026-08-17:** all seven playbooks now run `failed=0` against both
  `ws01` and `ws02` over SSH from a 2.16 control node, which turned up one defect (`helm.yml`,
  since fixed) that the `localhost`/2.20 evidence structurally could not reach. See
  [the `ws01`/`ws02` run](#the-ws01ws02-run-2026-08-17--and-the-one-defect-only-a-216-control-node-could-find).
  With [`cloud-cli/` closed the same way](MIGRATION2.md#known-follow-ups) on the same day, the
  outstanding remainder is `core/` and `misc/` — the item stays open until those are run too,
  and this run is the second of three reasons to expect it to find something when they are.
- **Renaming `_multi-user/`.** The underscore meant *staging*, sorting the tree apart from the
  live single-user directories it would replace. Those directories are gone — `core/` is the
  whole of the legacy tree and has no `_multi-user/` counterpart — so the prefix now marks a
  distinction that no longer exists, on 31 of the repo's 40 playbooks. Dropping it is cheaper
  than it looks — `ansible.cfg`'s `inventory` is relative and does not move — but it rewrites
  the `cd _multi-user` line in every documented command, in three READMEs and in
  `ansible.cfg`'s own header comment, and `_personal/` would want the same treatment or a
  stated reason not to. Worth doing as its own change rather than as the tail of a migration.
