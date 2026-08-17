# Core Playbooks (multi-user workstations)

Standalone playbooks that install the base CLI toolset, Node.js and mise on a **shared** Ubuntu
workstation. They are the multi-user successors to `core/`. See
[MIGRATION4.md](../../MIGRATION4.md) for the policy and the per-tool plan.

Run from `playbooks/`:

```bash
ansible-playbook core/<tool>.yml -e host=<inventory host or group>
```

## Conventions

These playbooks follow the same rules as [`misc/`](../misc/README.md),
[`cloud-cli/`](../cloud-cli/README.md) and [`container/`](../container/README.md) — root-owned
system paths, pinned versions, no writes to any `$HOME`, and a closing check that runs the tool
as an arbitrary uid (`setpriv --reuid=65534`) rather than as the connecting account. Unlike
`container/`, nothing here installs a runtime or needs a privilege grant: `core-tools.yml` and
`nodejs.yml` are apt-only and root-owned, and `mise.yml` needs nothing beyond the
`/etc/profile.d` hook it installs itself.

## core-tools.yml

Installs seventeen general-purpose CLI packages from the Ubuntu archive: `curl`, `gnupg`,
`lsb-release`, `git`, `git-lfs`, `git-secret`, `python3-pip`, `zip`, `unzip`, `vim`,
`net-tools`, `ncat`, `figlet`, `dos2unix`, `make`, `ca-certificates`, `aha` — all to
`/usr/bin` (or, for `ca-certificates`, a data file with no binary at all). There is no per-user
state and nothing added to a shell profile for any of them. `jq` has its own dedicated
playbook, [`jq.yml`](#jqyml).

Every package is pinned and version-compared against what's installed, and every package is
verified as an unprivileged user.

Two packages do not fit a plain `--version` check, and the verify command for **every**
package was confirmed against the actual installed binary rather than assumed:

- **`ca-certificates`** ships no binary. Verified by checking `/etc/ssl/certs/ca-certificates.crt`
  itself: present, non-empty, world-readable.
- **`aha`** has no reliably documented `--version` output. Verified by feeding it a real
  ANSI bold escape sequence and checking it came back as an actual HTML document, not merely
  echoed unchanged.

One finding only visible by actually running the playbook, not by reading the source:
`git-lfs` and `git-secret`'s unprivileged checks needed a `chdir` into the scratch
`HOME`, because `git` stats the current directory on startup and an unprivileged
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
`markdownlint.yml` (below) uses for a root-owned global npm install — puts real, pinned
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
request correctly. This is not particular to `nodejs.yml` — every `playbooks/` playbook that
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
it runs on a host neither `misc/` nor `container/` has touched yet.

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

`yq.yml` and `jq.yml` live as their own playbooks in this directory (below) rather than
bundled here, and `jsonnet.yml` lives in [`misc/`](../misc/README.md) — each pinned and
verified independently.

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

apt package pins are release-specific (see `shellcheck.yml`'s note on the same issue,
below); to override one, edit `modern_tools_packages` with `-e` as a JSON list, the same
pattern [`misc/grype-syft.yml`](../misc/README.md) uses for its tool list.

## jq.yml

Installs [jq](https://github.com/jqlang/jq) from the Ubuntu apt package, `/usr/bin/jq`,
root-owned. There is no per-user state and nothing to add to a shell profile.

A plain apt install, pinned by exact dpkg version the same way `shellcheck.yml` (below) is.

The unprivileged verification step pipes `{"a": 1}` into `jq '.a'` as `nobody` and checks
the output.

Version overrides:

```bash
ansible-playbook core/jq.yml -e host=ws01 -e jq_version=1.8.1-4ubuntu2
```

## markdownlint.yml

Installs [markdownlint-cli](https://github.com/igorshubovych/markdownlint-cli) via
`npm install -g`, root-owned. Node.js itself is a prerequisite provisioned elsewhere; this
playbook only checks for it, and fails loudly with setup instructions if it is missing.

- **Pinned version, not `@latest`.**
- **Version-aware idempotency.** The installed version is compared against the pin, not
  just the binary's presence.
- **npm's global prefix is read at run time, not assumed.** `npm config get prefix`
  differs depending on how Node.js was installed: a NodeSource-installed Node.js defaults
  it to `/usr` (`/usr/lib/node_modules`, `/usr/bin/markdownlint`), while Ubuntu's own
  `nodejs` apt package defaults it to `/usr/local` (`/usr/local/lib/node_modules`,
  `/usr/local/bin/markdownlint`). Both are root-owned system paths, so either is fine —
  but hardcoding one breaks the other.
- **Node-in-PATH guard**, accepting either system prefix: fails if `which node` resolves
  outside `/usr/bin/node` or `/usr/local/bin/node`, which would indicate a per-user
  version manager (nvm, fnm, ...) shadowing the system Node.js for the connecting account.

The unprivileged verification step lints a Markdown file with a deliberate heading-space
issue and checks the output for that specific rule (`MD018`). markdownlint writes its
findings to **stderr**, not stdout, and exits non-zero when it finds issues — both are the
expected, successful outcome of this check, not a failure of the playbook run.

Version overrides:

```bash
ansible-playbook core/markdownlint.yml -e host=ws01 -e markdownlint_cli_version=0.49.1
```

## shellcheck.yml

Installs [ShellCheck](https://github.com/koalaman/shellcheck) from the Ubuntu apt
package, `/usr/bin/shellcheck`, root-owned. There is no per-user state and nothing to
add to a shell profile.

Installed from the Ubuntu apt package rather than Homebrew — apt is current enough to use
directly, and unlike Homebrew, it's usable by every account on the host:

- **Pinned by exact dpkg version**, not just the semantic version. `shellcheck_version`
  is compared against `dpkg-query -W -f='${Version}' shellcheck`, which includes the
  Debian revision suffix (e.g. `-2`), so the idempotency check is exact.
- **The pin is Ubuntu-release-specific.** apt's candidate version for `shellcheck`
  differs between Ubuntu releases (`0.11.0-2` on 26.04 "resolute", `0.9.0-1` on 24.04
  "noble"). Overriding `shellcheck_version` only helps if that exact dpkg version is
  available from the target's configured apt sources.

The unprivileged verification step writes a throwaway script with a known issue
(unquoted `$1`) to `/tmp`, lints it as `nobody`, and checks for `SC2086` in the output.

Version overrides:

```bash
ansible-playbook core/shellcheck.yml -e host=ws01 -e shellcheck_version=0.9.0-1
```

## yq.yml

Installs [mikefarah/yq](https://github.com/mikefarah/yq) as a single static binary at
`/usr/local/bin/yq`, root-owned, mode `0755`. There is no per-user state and nothing to add
to a shell profile.

This is a release binary rather than a plain apt install, deliberately: per the
decision-order gotcha in `MIGRATION.md`, Ubuntu's apt `yq` is `kislyuk/yq`, a Python
wrapper around `jq` with entirely different syntax from mikefarah's Go `yq` that this
playbook installs. Silently swapping one for the other under the same command name would
break any script written against the Go one.

- **Checksum verification, but not from a checksums file.** yq's own published checksums file
  uses a bespoke multi-algorithm rhash table (`checksums_hashes_order` /
  `extract-checksum.sh` in the release), not the plain `hash  filename` format
  `gomplate.yml`/`hadolint.yml` (in [`misc/`](../misc/README.md)) parse. Instead, the
  playbook reads the SHA-256 `digest` GitHub computes and serves per release asset via its
  own releases API — simpler to consume and just as authoritative.
- **Architecture from facts.** `ansible_architecture` is mapped to the release asset suffix
  (`x86_64` → `amd64`, `aarch64` → `arm64`). Unmapped architectures fail with a clear message.
- **Version-aware idempotency.** The installed version (parsed from `yq --version` output) is
  compared against the pinned version before re-downloading.

The unprivileged verification step pipes `a: 1` into `yq e '.a' -` (reading from stdin) as
`nobody` and checks the output, proving yq's zero-configuration path.

Version overrides:

```bash
ansible-playbook core/yq.yml -e host=ws01 -e yq_version=4.53.3
```

## What is *not* here

There is no chrony playbook: Ubuntu 26.04 ships chrony pre-configured out of the box. Go and
Rust toolchains are also out of scope — this repo provisions a workstation that runs AI
coding agents rather than compiling with either. `mise.yml` above is the general-purpose way
to get a per-account language runtime.
