# Core Playbooks (multi-user workstations)

Standalone playbooks that install the base CLI toolset, Node.js and mise on a **shared** Ubuntu
workstation. They are the multi-user successors to `core/`, which was retired on 2026-08-16 once
all three were verified — the last directory of the original single-user tree, so its retirement
retired the entire legacy tree with it. See [MIGRATION4.md](../../MIGRATION4.md) for the policy
and the per-tool plan.

Run from `_multi-user/`:

```bash
ansible-playbook core/<tool>.yml -e host=<inventory host or group>
```

## Conventions

These playbooks follow the same rules as [`tools/`](../tools/README.md),
[`cloud-cli/`](../cloud-cli/README.md) and [`container/`](../container/README.md) — root-owned
system paths, pinned versions, no writes to any `$HOME`, and a closing check that runs the tool
as an arbitrary uid (`setpriv --reuid=65534`) rather than as the connecting account. Unlike
`container/`, nothing here installs a runtime or needs a privilege grant: `core-tools.yml` and
`nodejs.yml` were already apt-only and root-owned in their `core/` form, and `mise.yml`'s one
personal tail was a single `~/.bashrc` line, not a group membership.

## core-tools.yml

Installs nineteen general-purpose CLI packages from the Ubuntu archive: `curl`, `gnupg`,
`lsb-release`, `git`, `git-lfs`, `git-secret`, `python3-pip`, `jq`, `zip`, `unzip`, `vim`,
`net-tools`, `ncat`, `figlet`, `dos2unix`, `make`, `ca-certificates`, `cowsay`, `aha` — all to
`/usr/bin` (or, for `ca-certificates`, a data file with no binary at all). There is no per-user
state and nothing added to a shell profile for any of them.

The source playbook (`core/core-tools.yml`, renamed from `core/agent-base.yml` on 2026-08-14)
already installs to these same root-owned paths, so this migration is correctness work, not
reach work: every package is pinned and version-compared instead of `state: present` with no
guard, and every package is verified as an unprivileged user instead of not at all.

Three packages do not fit a plain `--version` check, and the verify command for **every**
package was confirmed against the actual installed binary rather than assumed:

- **`ca-certificates`** ships no binary. Verified by checking `/etc/ssl/certs/ca-certificates.crt`
  itself: present, non-empty, world-readable.
- **`cowsay`**'s Ubuntu package is the classic Perl build, which has no `--version` flag at all.
  Verified by running it and checking the message comes back inside the cow's speech bubble.
- **`aha`** has no reliably documented `--version` output either. Verified by feeding it a real
  ANSI bold escape sequence and checking it came back as an actual HTML document, not merely
  echoed unchanged.

One finding only visible by actually running the playbook, not by reading the source: Debian and
Ubuntu install `cowsay` to `/usr/games/cowsay`, and sudo's default `secure_path`
(`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin`, confirmed on this
host) does not include `/usr/games` — a bare `cowsay` on `PATH` resolves fine in an interactive
login shell and fails under `become` with "No such file or directory". The playbook calls it by
absolute path. `git-lfs` and `git-secret`'s unprivileged checks needed a `chdir` into the scratch
`HOME` for a related reason: `git` stats the current directory on startup, and an unprivileged
uid cannot even stat this repository's checkout path — the same class of defect MIGRATION2.md
found in `gcx-cli.yml`, here triggered by `git` itself rather than the tool being installed.

## nodejs.yml

Installs Node.js LTS from the NodeSource apt repository, plus Yarn Classic and pnpm as real
npm-global packages.

| Path | Contents |
| --- | --- |
| `/usr/bin/node`, `/usr/bin/npm`, `/usr/bin/npx` | from the NodeSource `nodejs` package |
| `/usr/bin/yarn`, `/usr/bin/pnpm` | real npm-global installs |
| `/etc/apt/sources.list.d/nodesource.sources` | repository definition, NodeSource's key inline |

**The Yarn/pnpm fix is the real work here.** NodeSource's `nodejs` package bundles Corepack,
which ships `/usr/bin/yarn` and `/usr/bin/pnpm` as its own dispatcher shims from the moment
`nodejs` is installed — before the source playbook's `npm install -g yarn` /
`npm install -g pnpm` tasks ever ran. Those were guarded on `creates: /usr/bin/yarn` /
`creates: /usr/bin/pnpm`, which Corepack's shims satisfy without ever being replaced, so on any
host that ran that playbook, "yarn" and "pnpm" were never this repo's install: they were
Corepack's dispatcher, which downloads whatever version is newest on the npm registry the first
time any account invokes it — non-deterministic across accounts and across time, into that
account's own cache.

The fix: `corepack disable` removes Corepack's shims, then
`npm install -g yarn@<version> pnpm@<version>` — the mechanism `tools/markdownlint.yml` already
established for a root-owned global npm install — puts real, pinned packages at the same paths.
The idempotency check never runs `yarn`/`pnpm` directly while a Corepack shim might still be at
that path, since doing so would trigger the exact non-deterministic download this playbook
exists to prevent; it resolves the binary with `readlink -f` to check whether the path leads into
Corepack's own tree, and separately asks npm's own install metadata (`npm ls -g <pkg>@<version>`)
rather than executing the binary at all. Only once that confirms a real npm-managed install does
the playbook invoke `yarn --version` / `pnpm --version`, for the summary and the unprivileged
smoke test.

A5 cleanup replaces NodeSource's `curl | bash` setup script with a declarative
`deb822_repository`: NodeSource's signing key carries no expiry, so it is pinned by content
inline (the `docker.yml`/`azure-cli.yml` form), and architecture comes from facts instead of the
hardcoded `amd64` the setup script's own internals assume.

**A confirmed, apt-module-level limitation worth knowing before bumping this pin.** `apt`'s
`allow_downgrade: true` is necessary but not always sufficient: on this host's `python3-apt`
(3.1.0ubuntu1), the module's synthetic priority-1001 version pin does not reliably beat an
already-installed *different* version unless the requested version is also apt's current
candidate — reproduced directly against `apt_pkg.Policy.get_candidate_ver()`, independently of
Ansible, while plain `apt-get install nodejs=<version> --allow-downgrades` resolves the identical
request correctly. This is not particular to `nodejs.yml` — every `_multi-user/` playbook that
pins an apt package the same way carries the same exposure — and it does not affect the normal
case this playbook is written for (installing the pinned version onto a host with an older or no
`nodejs` at all, which is what was actually verified). It only bites when the pin lags what apt
currently offers as the candidate; check `apt-cache policy nodejs` before overriding
`nodejs_version` to something other than the current candidate.

Version overrides — the stream is part of the pin, since NodeSource publishes one repository per
major version:

```bash
ansible-playbook core/nodejs.yml -e host=ws01 -e nodejs_version=24.19.0-1nodesource1
```

## mise.yml

Installs mise from its own apt repository.

| Path | Contents |
| --- | --- |
| `/usr/bin/mise` | the binary |
| `/etc/apt/sources.list.d/mise.sources` | repository definition |
| `/etc/profile.d/mise.sh` | live `eval "$(mise activate bash)"`, interactive shells only |

**The one genuine relocation in this directory.** The source playbook appended
`eval "$(mise activate bash)"` to the invoking account's own `~/.bashrc`, so only that one
account, and only shells it opened afterward, ever got mise's shell integration. Per
MIGRATION3.md's B3, a `PATH`/env-rewriting hook is neither a completion nor a static alias, so it
takes `/etc/profile.d/mise.sh` — the same destination and the same shape (a live `eval`, not a
captured snapshot) as `tools/modern-cli-tools.yml`'s `fzf.sh`. `/etc/bash.bashrc` needs the
`/etc/profile.d` bootstrap for non-login interactive shells to read it, which this playbook lays
down defensively in case it runs on a host neither `tools/` nor `container/` has touched yet.

**mise writes to `$HOME` on a plain `--version`, so this playbook never runs mise itself as
root.** Confirmed live: `HOME=<scratch> mise --version` creates
`<scratch>/.cache/mise/latest-version`, a self-update-check cache, from the plainest possible
invocation. The install and post-install version checks compare `dpkg-query` output instead —
running `mise --version` as root would leave `/root/.cache/mise` behind, which is exactly what
MIGRATION3.md's B2 forbids ("no task ... may write ... under any account's `$HOME`, including the
invoker's"). The unprivileged checks give mise a scratch, writable `HOME` for the same reason
every other tool in this repo that touches `$HOME` gets one.

**A separate, confirmed-harmless quirk.** A `[WARN] migrate: error parsing config file: ...` line
names the *real* invoking account's `~/.config/mise/config.toml` even when `$HOME` has been
overridden — confirmed with `strace` and `env -i` that this one path resolves via the OS user
database rather than `$HOME`, unlike every other piece of mise state (including the cache write
above), which does respect it. It is a read of a path that does not exist for uid 65534 or for
root, so it is noise, not a defect this playbook works around.

The repository's signing key expires 2028-01-02, so it is fetched by URL each run and only its
fingerprint is pinned (the `github-cli.yml`/`kubectl.yml` form).

Version overrides:

```bash
ansible-playbook core/mise.yml -e host=ws01 -e mise_version=2026.8.6
```

## What is *not* here

`core/README.md`'s chrony section was never a playbook (Ubuntu 26.04 ships chrony pre-configured)
and got no multi-user successor; it is recoverable from git history
(`git log --diff-filter=D -- core/README.md`) along with the rest of that file. The Go and Rust
toolchains that used to live in this directory (`core/golang.yml`, `core/rust.yml`) were retired
outright on 2026-08-10 as out of scope for a workstation that runs AI coding agents rather than
compiling with either (`git log --diff-filter=D -- core/golang.yml core/rust.yml` has the
history). `mise.yml` above is the general-purpose replacement for a per-account runtime, same as
it was in `core/`.

## Status

| Playbook | Successor to | Pinned | Status |
| --- | --- | --- | --- |
| `core-tools.yml` | `core/core-tools.yml` | 19 packages, see the playbook's `vars` | Verified (localhost) |
| `nodejs.yml` | `core/nodejs.yml` | nodejs 24.19.0-1nodesource1, yarn 1.22.22, pnpm 11.21.0 | Verified (localhost) |
| `mise.yml` | `core/mise.yml` | 2026.8.6 | Verified (localhost) |

All three are migrated, and these are now the only generation: `core/` was deleted on 2026-08-16
once every successor was verified, so the "Successor to" column names files that exist only in
git history (`git log --diff-filter=D -- core/`). What the retirement gate did *not* cover is
below, and it is worth reading: the successors were verified against a real host, but never
against a *remote* one — see [MIGRATION4.md](../../MIGRATION4.md#known-follow-ups).

"Verified (localhost)" carries the same two caveats as everything else in `_multi-user/`: the
runs were made under ansible-core 2.20 with `ansible_connection=local`, so they exercise neither
the 24.04 control node nor the SSH path. `ws01`/`ws02` have never been provisioned by either
generation.
