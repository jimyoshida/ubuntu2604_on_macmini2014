# Container & Kubernetes Playbooks (multi-user workstations)

Standalone playbooks that install container and Kubernetes tooling on a **shared** Ubuntu
workstation. They are the multi-user successors to `container/`. See
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

Both accept a comma-separated string or a YAML list, matching `_personal/`'s
`target_users`:

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

## Status

| Playbook | Successor to | Pinned | Status |
| --- | --- | --- | --- |
| `devcontainers.yml` | `container/devcontainers.yml` | 0.88.0 | Verified (localhost) |
| `podman.yml` | `container/podman.yml` | podman 5.7.0+ds2-3build1, podman-compose 1.5.0-2 | Verified (localhost) |

The remaining five (`docker`, `kubectl`, `helm`, `kind`, `minikube`) are not yet written;
see [MIGRATION3.md](../../MIGRATION3.md#migration-status). `container/krew.yml` is
[retired](../../README.md#retired-containerkrewyml) rather than migrated, so there will be
no `krew.yml` here.

"Verified (localhost)" carries the same two caveats as everything else in `_multi-user/`:
the runs were made under ansible-core 2.20 with `ansible_connection=local`, so they
exercise neither the 24.04 control node nor the SSH path. `ws01`/`ws02` have never been
provisioned by either generation.
