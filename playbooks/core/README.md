# Core Playbooks (multi-user workstations)

Standalone playbooks that install the base CLI toolset, Node.js, mise, ansible-core, the .NET
SDK, PowerShell and OpenJDK on a **shared** Ubuntu workstation, to root-owned system paths usable
by every account on the host. See [POLICY.md](../POLICY.md) for the rules they follow.

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

Installs twenty-two general-purpose CLI packages from the Ubuntu archive: `curl`, `gnupg`,
`lsb-release`, `git`, `git-lfs`, `git-secret`, `python3-pip`, `cpanminus`, `mailutils`, `jq`,
`xlsx2csv`, `docx2txt`, `zip`, `unzip`, `net-tools`, `ncat`, `figlet`, `dos2unix`, `make`,
`parallel`, `ca-certificates`, `aha` — all to `/usr/bin` (or, for `ca-certificates`, a data file
with no binary at all). Nothing is added to a shell profile, and the only per-user state any of
them creates is GNU parallel's: running a job — not `--version`, which writes nothing — makes
`~/.parallel/tmp` in the invoking account's own home, where it belongs. The install task passes
`install_recommends: false`, added for `mailutils` (whose only recommendation is a full
`default-mta` like postfix) but applied across the board so no package here pulls in more than
the CLI tool asked for.

Every package is pinned and version-compared against what's installed, and every package is
verified as an unprivileged user.

Four packages do not fit a plain `--version` check, and the verify command for **every**
package was confirmed against the actual installed binary rather than assumed:

- **`ca-certificates`** ships no binary. Verified by checking `/etc/ssl/certs/ca-certificates.crt`
  itself: present, non-empty, world-readable.
- **`aha`** has no reliably documented `--version` output. Verified by feeding it a real
  ANSI bold escape sequence and checking it came back as an actual HTML document, not merely
  echoed unchanged.
- **`parallel`** could be checked with a version string, but running jobs is the whole point
  of it, so its check runs three and compares their combined output — the one verify command
  here that does real work. Ubuntu's package prints no citation notice (confirmed: an
  unprivileged run writes nothing at all to stderr), so nothing has to be silenced for it.
- **`docx2txt`** has no `--version` output at all. Verified the same way as `aha`: builds a
  minimal real `.docx` (a zip containing a bare `word/document.xml` and
  `word/_rels/document.xml.rels`) and checks the extracted text comes back correctly.

One finding only visible by actually running the playbook, not by reading the source:
`git-lfs` and `git-secret`'s unprivileged checks needed a `chdir` into the scratch
`HOME`, because `git` stats the current directory on startup and an unprivileged
uid cannot even stat this repository's checkout path — the trap
[POLICY.md's C6](../POLICY.md) describes, here triggered by `git` itself rather than the
tool being installed.

## nodejs.yml

Installs Node.js LTS from the NodeSource apt repository, plus Yarn Classic, pnpm and two audit
report renderers as real npm-global packages.

| Path | Contents |
| --- | --- |
| `/usr/bin/node`, `/usr/bin/npm`, `/usr/bin/npx` | from the NodeSource `nodejs` package |
| `/usr/bin/yarn`, `/usr/bin/pnpm` | real npm-global installs |
| `/usr/bin/audit-export`, `/usr/bin/yarn-audit-html` | npm-global installs — render `npm`/`yarn audit --json` as HTML |
| `/etc/apt/sources.list.d/nodesource.sources` | repository definition, NodeSource's key inline |

Every npm-global package comes from one list (`nodejs_npm_globals`), which drives the install,
the per-package `npm ls` pin check and the world-readable pass alike, so adding one is a single
list entry.

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

### The audit report renderers

`audit-export` renders `npm audit --json` (it also accepts pnpm's and yarn's) and
`yarn-audit-html` renders `yarn audit --json` and Berry's `yarn npm audit --json`. Each is
verified by feeding it a synthetic advisory and asserting the module name survives into the
report — proof it parsed the input rather than emitting a template.

**`audit-export` embeds its findings base64-encoded** in the page rather than as markup, so its
check decodes the payload before asserting on it. Grepping the HTML for a package name finds
nothing even when the report is perfectly good — worth knowing before writing a check against
it. `yarn-audit-html` needs no such decoding, but it does need `npm ls` rather than `--version`
for its pin check, because it implements no `--version` flag at all (`error: unknown option
'--version'`).

**`npm-audit-html` is deliberately not installed**, and the reason is recorded so nobody adds it
back by reflex. Its templates read the `advisories` key of npm v6's audit JSON; npm 7 replaced
that with `auditReportVersion: 2` and a `vulnerabilities` map, and the package has had no
release since 2020-11-11. Measured here before it was dropped: a real `npm audit --json` for a
project with a **critical** lodash advisory rendered to a report **byte-for-byte identical** to
one rendered from an empty audit, with no mention of lodash in it. It installs, it runs, and it
reports nothing — worse than not having it. `audit-export` reads the same audit correctly, which
is why it takes that place.

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
[POLICY.md's B3](../POLICY.md) on why a `PATH`/env-rewriting hook belongs there and not among
completions or static aliases). `/etc/bash.bashrc` needs the `/etc/profile.d` bootstrap for
non-login interactive shells to read it, which this playbook lays down defensively in case
it runs on a host neither `misc/` nor `container/` has touched yet.

**mise writes to `$HOME` on a plain `--version`, so this playbook never runs mise itself as
root.** Confirmed live: `HOME=<scratch> mise --version` creates
`<scratch>/.cache/mise/latest-version`, a self-update-check cache, from the plainest possible
invocation. The install and post-install version checks compare `dpkg-query` output instead —
running `mise --version` as root would leave `/root/.cache/mise` behind, which is exactly what
[POLICY.md's B2](../POLICY.md) forbids ("no task ... may write ... under any account's `$HOME`, including the
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

## dotnet.yml

Installs the .NET SDK from the Ubuntu archive.

| Path | Contents |
| --- | --- |
| `/usr/bin/dotnet` | the CLI |
| `/usr/lib/dotnet/` | SDK, runtimes, targeting packs, templates |

**No Microsoft apt repository and no vendor key**: Ubuntu 26.04 carries .NET 10 itself, as
`dotnet-sdk-10.0`, which pulls the host, runtime, ASP.NET runtime, targeting packs, templates
and the AOT components with it — thirteen packages in all. That is a change from earlier
releases, where `packages.microsoft.com` was the only source.

**Per-user state is the norm with .NET, and this playbook creates none of it.** Each account
gets its own `~/.dotnet` (CLI state, first-run sentinel) and `~/.nuget/packages` (the package
cache) on first use. A shared NuGet cache is deliberately not created: one account's restore
should not decide what another builds against.

That same fact makes the CLI unsafe to run as root here — `dotnet --version` alone creates
`/root/.dotnet`, which [POLICY.md's B2](../POLICY.md) forbids — so the idempotency and version checks read
`dpkg-query` (as `mise.yml` does) and every actual `dotnet` invocation is unprivileged with a
scratch `HOME`.

The unprivileged verification is the strongest form available: it creates a console project
from the SDK's own template, builds it and runs it, so the templates, the compiler, the runtime
and NuGet restore are all exercised for an account that did no setup of its own.

Telemetry is left to each account (`DOTNET_CLI_TELEMETRY_OPTOUT=1`), the same way
[`misc/dvc.yml`](../misc/README.md#dvcyml) leaves DVC's analytics alone; the playbook sets it
only for its own checks.

This is the prerequisite for [`misc/dotnet-tools.yml`](../misc/README.md#dotnet-toolsyml).

Version overrides:

```bash
ansible-playbook core/dotnet.yml -e host=ws01 -e dotnet_version=10.0.110-0ubuntu1~26.04.1
```

## pwsh.yml

Installs [PowerShell](https://learn.microsoft.com/powershell/) 7.6.5 from the upstream binary
archive, in the versioned-directory-plus-symlink shape
[`misc/maven.yml`](../misc/README.md#mavenyml) uses.

| Path | Contents |
| --- | --- |
| `/usr/local/lib/powershell/<version>/` | the unpacked release (~171 MB) |
| `/usr/local/bin/pwsh` | symlink to that version's `pwsh` |

**Not apt, and the reason is measured.** Microsoft publishes **no `powershell` package for
Ubuntu 26.04 at all** — its 26.04 repository (`packages.microsoft.com/ubuntu/26.04/prod`, suite
`resolute`) carries none at any version, checked 2026-08-17. Installing from apt would mean
pointing a 26.04 host at the 24.04 `noble` suite and hoping the dependencies line up. The binary
archive Microsoft publishes for exactly this case is self-contained: `libicu` is its only real
system dependency, and `ldd` reports nothing missing for `pwsh`. The pin can then be the current
release, verified against the SHA-256 GitHub publishes for the asset.

### Root never runs pwsh here

PowerShell writes `~/.cache/powershell` (including `telemetry.uuid` and startup profile data),
`~/.config/powershell` and `~/.local/share/powershell` — confirmed live, the cache appears on the
plainest possible invocation. Running it as root would leave that under `/root`, which
[POLICY.md's B2](../POLICY.md) forbids, so the idempotency check reads the filesystem (the versioned path and
the symlink target) and every `pwsh` invocation is unprivileged with a scratch `HOME`.

### The AllUsers module scope is asserted, not assumed

No modules are installed — which set a workstation needs is not this playbook's decision — but
the check does assert that `/usr/local/share/powershell/Modules` is on `PSModulePath` for an
unprivileged account. That is what makes a later `Install-Module -Scope AllUsers` land somewhere
every account can read rather than in one account's `~/.local/share/powershell`, and a tarball
install could plausibly have left it off.

The rest of the unprivileged check is real work: a script builds an object, round-trips it
through `ConvertTo-Json`/`ConvertFrom-Json` and reports the version, so the cmdlet pipeline and
the type system are exercised rather than a version string. It runs from a file rather than
`-Command`, which keeps PowerShell source out of four layers of YAML, Jinja and shell quoting.

Telemetry is left to each account (`POWERSHELL_TELEMETRY_OPTOUT`), the same way
[`misc/dvc.yml`](../misc/README.md#dvcyml) leaves DVC's analytics alone.

Version overrides:

```bash
ansible-playbook core/pwsh.yml -e host=ws01 -e pwsh_version=7.6.5
```

## openjdk.yml

Installs OpenJDK from the Ubuntu archive's `default-jdk` metapackage.

| Path | Contents |
| --- | --- |
| `/usr/bin/java`, `/usr/bin/javac` | via `update-alternatives` |
| `/usr/lib/jvm/java-<major>-openjdk-<arch>/` | the JDK itself |

**One pinned package for every Java-based playbook in this repository to share, not three.**
`misc/maven.yml`, `cloud-cli/jenkins-cli.yml` and `misc/zap.yml` each used to install their own
JDK or JRE package inline — `default-jdk-headless`, `default-jre-headless` and `default-jre`
respectively — which meant the same underlying package could end up pinned three different ways
across three files on one host. `default-jdk` is not headless, and pulls in the full JDK rather
than just a JRE, deliberately: its dependency chain (`default-jdk` → `default-jre` +
`default-jdk-headless`; `default-jdk-headless` → `default-jre-headless` + `openjdk-<N>-jdk`)
covers the union of what all three consumers need — `javac` for Maven, a runtime for the Jenkins
CLI, and the non-headless runtime ZAP's desktop UI needs — confirmed with
`apt-cache depends default-jdk`.

Each of the three downstream playbooks now only checks for the binary it needs (`javac` or
`java`) and fails with instructions to run this playbook first, the shape
[`misc/dotnet-tools.yml`](../misc/README.md#dotnet-toolsyml) and
[`cloud-cli/azure-pwsh.yml`](../cloud-cli/README.md#azure-pwshyml) use for
[`dotnet.yml`](#dotnetyml) and [`pwsh.yml`](#pwshyml).

**No scratch `HOME` in the verification, unlike every other Java-based playbook here.** The JVM
reads `user.home` from the OS user database, not from `$HOME` — confirmed live,
`HOME=/nonexistent java ...` still resolves `user.home` to the real account's passwd entry —
which is exactly the trap [`misc/maven.yml`](../misc/README.md#mavenyml) and
[`misc/zap.yml`](../misc/README.md#zapyml) document for their own per-tool state (`~/.m2`,
`~/.ZAP`). A plain compile-and-run never touches `user.home` at all, so the check needs only a
writable `chdir`, not a scratch `HOME`: an unprivileged account compiles a real program with
`javac` and runs it with `java`, end to end.

This is the prerequisite for [`misc/maven.yml`](../misc/README.md#mavenyml),
[`cloud-cli/jenkins-cli.yml`](../cloud-cli/README.md#jenkins-cliyml) and
[`misc/zap.yml`](../misc/README.md#zapyml).

Version overrides:

```bash
ansible-playbook core/openjdk.yml -e host=ws01 -e openjdk_version=2:1.25-77
```

## modern-tools.yml

Installs 13 modern CLI tool replacements from apt, root-owned, at `/usr/bin` (no per-user
state, nothing added to a shell profile for any of them):

| Tool | apt package | Binary |
| --- | --- | --- |
| gum, fzf, eza, lsd, duf, procs, gdu, htop, glow | same name | same name |
| ripgrep | `ripgrep` | `rg` |
| bat | `bat` | `batcat` (symlinked to `/usr/local/bin/bat`) |
| fd | `fd-find` | `fdfind` (symlinked to `/usr/local/bin/fd`) |
| dust | `du-dust` | `dust` |

**Two of them ship under a different binary name**, because the upstream name is already
taken on Debian: `bat` is installed as `batcat` (the bacula tools own `/usr/bin/bat`) and `fd`
as `fdfind` (`fdclone`, a file manager, owns `/usr/bin/fd`). Both are published under their
upstream name from `/usr/local/bin`, which precedes `/usr/bin` on the default `PATH`, rather
than left to each account to alias for itself — and the verification runs them *through* `PATH`
as `nobody`, so it proves the symlink resolves and wins rather than merely existing.

Also lays down:

| Path | Contents |
| --- | --- |
| `/etc/profile.d/fzf.sh` | `eval "$(fzf --bash)"` — fzf key bindings and completion |

`yq.yml` lives as its own playbook in this directory (below) rather than bundled here, and
`jsonnet.yml` lives in [`misc/`](../misc/README.md) — each pinned and verified independently.
`jq` used to be split out the same way, but now lives in [`core-tools.yml`](#core-toolsyml)
instead, alongside the other plain-apt CLI tools.

**No vendor apt repo needed for `gum` and `glow`.** Ubuntu 26.04 ("resolute") carries apt
packages for both directly (`gum` 0.17.0-1, `glow` 2.1.1-1), so a single apt install covers
the whole bundle with no vendor repository required.

**`llhttp` is not part of this bundle.** apt's `eza` package declares `libgit2-1.9` etc. as
proper package dependencies, so no separate library symlink is needed for it to find its
runtime library.

fzf's key bindings need `/etc/profile.d` to actually be read by interactive shells, which is
not true by default for a non-login shell (e.g. a plain SSH session) on stock Ubuntu — see
[POLICY.md's B3](../POLICY.md). This playbook adds that hook to `/etc/bash.bashrc`; the
task is an idempotent no-op for any other playbook that adds the same hook.

The unprivileged verification step runs every tool's `--version` as `nobody`, then separately
opens a non-login interactive `bash -i` shell as the same user and checks that fzf's
`__fzf_select__` function is defined — proving the `/etc/profile.d` → `/etc/bash.bashrc` chain
actually works end-to-end for a real interactive session, not just that the binaries exist.

apt package pins are release-specific (see `shellcheck.yml`'s note on the same issue,
below); to override one, edit `modern_tools_packages` with `-e` as a JSON list, the same
pattern [`misc/grype-syft.yml`](../misc/README.md) uses for its tool list.

## ansible.yml

Installs [ansible-core](https://github.com/ansible/ansible) from the Ubuntu apt package —
ten CLI entrypoints under `/usr/bin`, root-owned — plus five pinned Galaxy collections into
`/usr/share/ansible/collections`. There is no per-user state and nothing to add to a shell
profile: that directory is already the system-wide half of ansible-core's default
`COLLECTIONS_PATH` (`~/.ansible/collections:/usr/share/ansible/collections`), so every account
picks the collections up with no environment variable and no config of its own.

| Path | Contents |
| --- | --- |
| `/usr/bin/ansible{,-config,-console,-doc,-galaxy,-inventory,-playbook,-pull,-test,-vault}` | from the `ansible-core` apt package |
| `/usr/share/ansible/collections` | `ansible.posix`, `community.general`, `community.docker`, `community.postgresql`, `amazon.aws` |

**ansible-core, not the `ansible` community bundle.** apt carries both: `ansible`
(13.1.0+dfsg-1ubuntu1 on 26.04) is the batteries-included collection bundle that depends on
`ansible-core`, a much larger install with its own collection versioning. This playbook pins
the engine and exactly the five collections above, and neither installs nor removes the
bundle — though it does declare `Depends: ansible-core (>= 2.18.0~)`, so pinning
`ansible_core_version` under that floor makes apt refuse the transaction rather than
silently break the bundle.

**The bundle, where it is installed, is also what makes the collection handling non-trivial.**
It ships four of these five collections under `/usr/lib/python3/dist-packages/ansible_collections`
at its own versions (measured on ws01: `amazon.aws` 10.1.2, `ansible.posix` 2.1.0,
`community.docker` 5.0.4, `community.general` 12.1.0, `community.postgresql` 4.2.0 — all older
than the pins here except postgresql, which matches exactly). Two consequences the playbook is
built around:

- **`ansible-galaxy collection install` silently does nothing** when the collection is visible
  in *any* path, including that bundle's. Confirmed live with `community.postgresql` 4.2.0: the
  install reported success-by-omission and nothing landed in the target path. Hence
  `--force-with-deps` — the `deps` half matters too, or a dependency that exists only in the
  bundle's tree (`community.library_inventory_filtering_v1`, for `community.docker`) is skipped
  as well, leaving this install dependent on a package it does not own.
- **The idempotency check reads the version installed at the target path**, not whether the
  collection is installed at all — and it keys on `<path>/ansible_collections`, which is what
  `ansible-galaxy collection list --format json` reports, not the path passed to `-p`.

**`ansible` writes to `$HOME` on a plain `--version`**, so, exactly as in `mise.yml`, this
playbook never runs ansible itself as root: `dpkg-query` supplies both the idempotency check and
the version verification. `ansible-galaxy` is worse — it writes a `galaxy_token` and a
`galaxy_cache/`— and it is the one command here that *has* to run as root, so it gets a scratch
`HOME`/`ANSIBLE_HOME` that does not outlive the play.

**A scratch `$HOME` alone is not enough for the unprivileged checks**, which is the one genuinely
non-obvious finding here. ansible resolves `remote_tmp` (default `~/.ansible/tmp`) against the
*remote user's* home as read from the OS user database, and identifies that user from
`USER`/`LOGNAME` in the environment — not from `$HOME`. Under `become: true` those are still
root, so a smoke test that only overrides `HOME` has ansible try to `mkdir /root/.ansible/tmp` as
uid 65534 and fail with "Failed to create temporary directory"; clearing `USER`/`LOGNAME` instead
just moves the target to nobody's `/nonexistent`, which is no more writable. Both were reproduced
directly on a target, which is why `ANSIBLE_REMOTE_TEMP` is set explicitly rather than inferred.

The unprivileged verification is three checks as `nobody`, all of them level-2 rather than a bare
`--version`:

1. `ansible --version` reports the pinned core version.
2. For each collection, `ansible-doc -t module -F <collection>` prints the file path ansible's own
   plugin loader resolved — asserted to be under `/usr/share/ansible/collections`. This is the
   empirical proof that a configured collections path beats the bundle's copies on the PYTHONPATH,
   and incidentally that the installed tree is world-readable.
3. A real one-task playbook runs over a local connection, exercising inventory parsing, Jinja
   templating, a filter plugin loaded out of `community.general`, and the module transfer that
   needs a writable temp directory. `ANSIBLE_NOCOWS=1` keeps cowsay, where it is installed, from
   decorating the output the check parses.

Collection pins are the latest release of each on galaxy.ansible.com as of 2026-08-17, read from
the Galaxy v3 API rather than assumed. Galaxy publishes often — re-check before treating them as
current:

```bash
curl -sS https://galaxy.ansible.com/api/v3/plugin/ansible/content/published/collections/index/community/general/ | jq .highest_version
```

Version overrides — the apt pin is Ubuntu-release-specific in the same way `shellcheck.yml`'s is;
each collection has its own variable:

```bash
ansible-playbook core/ansible.yml -e host=ws01 -e ansible_core_version=2.20.1-1
ansible-playbook core/ansible.yml -e host=ws01 -e ansible_collection_community_general_version=13.3.0
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
apt gotcha in [INSTALL-MECHANISMS.md](../INSTALL-MECHANISMS.md), Ubuntu's apt `yq` is
`kislyuk/yq`, a Python
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
