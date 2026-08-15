# Core Playbooks (multi-user workstations)

Standalone playbooks that install the base CLI toolset, Node.js and mise on a **shared** Ubuntu
workstation. They are the multi-user successors to `core/`. See
[MIGRATION4.md](../../MIGRATION4.md) for the policy and the per-tool plan.

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
`nodejs.yml` are apt-only and root-owned, and `mise.yml` needs nothing beyond the
`/etc/profile.d` hook it installs itself.

## core-tools.yml

Installs nineteen general-purpose CLI packages from the Ubuntu archive: `curl`, `gnupg`,
`lsb-release`, `git`, `git-lfs`, `git-secret`, `python3-pip`, `jq`, `zip`, `unzip`, `vim`,
`net-tools`, `ncat`, `figlet`, `dos2unix`, `make`, `ca-certificates`, `cowsay`, `aha` — all to
`/usr/bin` (or, for `ca-certificates`, a data file with no binary at all). There is no per-user
state and nothing added to a shell profile for any of them.

Every package is pinned and version-compared against what's installed, and every package is
verified as an unprivileged user.

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

**The Yarn/pnpm handling is the tricky part here.** NodeSource's `nodejs` package bundles
Corepack, which ships `/usr/bin/yarn` and `/usr/bin/pnpm` as its own dispatcher shims from
the moment `nodejs` is installed. Left alone, those shims download whatever version is
newest on the npm registry the first time any account invokes them — non-deterministic
across accounts and across time, into that account's own cache.

The fix: `corepack disable` removes Corepack's shims, then
`npm install -g yarn@<version> pnpm@<version>` — the same mechanism
`tools/markdownlint.yml` uses for a root-owned global npm install — puts real, pinned
packages at the same paths. The idempotency check never runs `yarn`/`pnpm` directly while a
Corepack shim might still be at that path, since doing so would trigger the exact
non-deterministic download this playbook exists to prevent; it resolves the binary with
`readlink -f` to check whether the path leads into Corepack's own tree, and separately asks
npm's own install metadata (`npm ls -g <pkg>@<version>`) rather than executing the binary at
all. Only once that confirms a real npm-managed install does the playbook invoke
`yarn --version` / `pnpm --version`, for the summary and the unprivileged smoke test.

Repository setup uses a declarative `deb822_repository`: NodeSource's signing key carries no
expiry, so it is pinned by content inline (the `docker.yml`/`azure-cli.yml` form), and
architecture comes from facts.

**A confirmed, apt-module-level limitation worth knowing before bumping this pin.** `apt`'s
`allow_downgrade: true` is necessary but not always sufficient: on this host's `python3-apt`
(3.1.0ubuntu1), the module's synthetic priority-1001 version pin does not reliably beat an
already-installed *different* version unless the requested version is also apt's current
candidate — reproduced directly against `apt_pkg.Policy.get_candidate_ver()`, independently of
Ansible, while plain `apt-get install nodejs=<version> --allow-downgrades` resolves the identical
request correctly. This is not particular to `nodejs.yml` — every `_multi-user/` playbook that
pins an apt package the same way carries the same exposure — and it does not affect the normal
case this playbook is written for (installing the pinned version onto a host with an older or no
`nodejs` at all). It only bites when the pin lags what apt currently offers as the candidate;
check `apt-cache policy nodejs` before overriding `nodejs_version` to something other than the
current candidate.

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

mise's shell integration goes to `/etc/profile.d/mise.sh` system-wide — the same
destination and the same shape (a live `eval`, not a captured snapshot) as
`modern-tools.yml`'s `fzf.sh` — rather than into any one account's `~/.bashrc` (see
MIGRATION3.md's B3 on why a `PATH`/env-rewriting hook belongs there and not among
completions or static aliases). `/etc/bash.bashrc` needs the `/etc/profile.d` bootstrap for
non-login interactive shells to read it, which this playbook lays down defensively in case
it runs on a host neither `tools/` nor `container/` has touched yet.

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

## modern-tools.yml

Installs 12 modern CLI tool replacements from apt, root-owned, at `/usr/bin` (no per-user
state, nothing added to a shell profile for any of them):

| Tool | apt package | Binary |
| --- | --- | --- |
| gum, fzf, eza, lsd, duf, procs, gdu, htop, glow | same name | same name |
| ripgrep | `ripgrep` | `rg` |
| bat | `bat` | `batcat` (symlinked to `/usr/local/bin/bat`) |
| dust | `du-dust` | `dust` |

Also lays down:

| Path | Contents |
| --- | --- |
| `/etc/profile.d/fzf.sh` | `eval "$(fzf --bash)"` — fzf key bindings and completion |

`yq.yml`, `jq.yml` and `jsonnet.yml` live as their own playbooks in
[`tools/`](../tools/README.md) rather than bundled here, each pinned and verified
independently.

**No vendor apt repo needed for `gum` and `glow`.** Ubuntu 26.04 ("resolute") carries apt
packages for both directly (`gum` 0.17.0-1, `glow` 2.1.1-1), so a single apt install covers
the whole bundle with no vendor repository required.

**`llhttp` is not part of this bundle.** apt's `eza` package declares `libgit2-1.9` etc. as
proper package dependencies, so no separate library symlink is needed for it to find its
runtime library.

fzf's key bindings need `/etc/profile.d` to actually be read by interactive shells, which is
not true by default for a non-login shell (e.g. a plain SSH session) on stock Ubuntu — see
"Known follow-ups" in `MIGRATION.md`. This playbook adds that hook to `/etc/bash.bashrc`; the
task is an idempotent no-op for any other playbook that adds the same hook.

The unprivileged verification step runs every tool's `--version` as `nobody`, then separately
opens a non-login interactive `bash -i` shell as the same user and checks that fzf's
`__fzf_select__` function is defined — proving the `/etc/profile.d` → `/etc/bash.bashrc` chain
actually works end-to-end for a real interactive session, not just that the binaries exist.

apt package pins are release-specific (see `tools/shellcheck.yml`'s note on the same issue);
to override one, edit `modern_tools_packages` with `-e` as a JSON list, the same pattern
`tools/grype-syft.yml` uses for its tool list.

## What is *not* here

There is no chrony playbook: Ubuntu 26.04 ships chrony pre-configured out of the box. Go and
Rust toolchains are also out of scope — this repo provisions a workstation that runs AI
coding agents rather than compiling with either. `mise.yml` above is the general-purpose way
to get a per-account language runtime.
