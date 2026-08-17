# Misc Playbooks (multi-user workstations)

Standalone playbooks that install developer tooling on a **shared** Ubuntu workstation, to
root-owned system paths usable by every account on the host rather than into one account's
home directory.

Run from `playbooks/`:

```bash
ansible-playbook misc/<tool>.yml -e host=<inventory host or group>
```

## Conventions

Every playbook here follows the same rules, so that a tool installed once is usable by
every account on the host, including accounts created later:

1. **Root-owned system paths only.** Binaries go to `/usr/local/bin` (or apt). No
   Homebrew: `/home/linuxbrew` is owned by whoever installed it, and Homebrew upstream
   does not support multi-user installs.
2. **Shell configuration goes to `/etc`**, never to `~/.bashrc`. Environment variables in
   `/etc/environment` (applies to login and SSH sessions via PAM); interactive-only
   settings such as key bindings and completions in `/etc/profile.d/<tool>.sh`, with
   `/etc/bash.bashrc` sourcing it for non-login interactive shells.
3. **World-readable install trees.** Explicitly set `mode: 'u=rwX,go=rX'` rather than
   relying on the umask of whoever ran the playbook.
4. **Pinned versions** in the play's `vars`, overridable with `-e`.
5. **Verified unprivileged.** Each playbook ends with a check that runs the tool as an
   arbitrary uid (`setpriv --reuid=65534`), not as the connecting user, so a
   single-user regression fails the run instead of going unnoticed.

## bats.yml

Installs the [Bats](https://github.com/bats-core/bats-core) testing framework and its
helper libraries from upstream git tags.

| Path | Contents |
| --- | --- |
| `/usr/local/bin/bats` | executable (via upstream `install.sh`) |
| `/usr/local/libexec/bats-core/`, `/usr/local/lib/bats-core/` | internals |
| `/usr/local/src/bats-core/` | checked-out source, kept for upgrades |
| `/usr/lib/bats/bats-support/` | helper library |
| `/usr/lib/bats/bats-assert/` | helper library |

`/usr/lib/bats` is bats-core's built-in default for `BATS_LIB_PATH`
(`libexec/bats-core/bats`: `BATS_LIB_PATH=${BATS_LIB_PATH-/usr/lib/bats}`), so test files
resolve the helpers with no per-user configuration:

```bash
setup() {
  bats_load_library bats-support
  bats_load_library bats-assert
}
```

The playbook also writes `BATS_LIB_PATH` to `/etc/environment` to make the location
explicit and to survive an upstream change of that default.

Version overrides:

```bash
ansible-playbook misc/bats.yml -e host=ws01 -e bats_core_version=1.13.0
```

## gomplate.yml

Installs [gomplate](https://github.com/hairyhenderson/gomplate) as a single static binary
at `/usr/local/bin/gomplate`, root-owned, mode `0755`. There is no per-user state and
nothing to add to a shell profile.

- **Version-aware idempotency.** The installed version is compared against the pin before
  re-downloading.
- **Checksum verification.** The SHA-256 is read from the release's published
  `checksums-v<version>_sha256.txt` at run time, so changing the version stays a one-flag
  change instead of also requiring a hardcoded hash update.
- **Architecture from facts.** `ansible_architecture` is mapped to the release asset
  suffix (`x86_64` → `amd64`, `aarch64` → `arm64`) rather than assuming amd64. Unmapped
  architectures fail with a clear message.

Version overrides:

```bash
ansible-playbook misc/gomplate.yml -e host=ws01 -e gomplate_version=4.3.3
```

## grype-syft.yml

Installs [grype](https://github.com/anchore/grype) (vulnerability scanner) and
[syft](https://github.com/anchore/syft) (SBOM generator) as single static binaries at
`/usr/local/bin/grype` and `/usr/local/bin/syft`, root-owned, mode `0755`. There is no
per-user state and nothing to add to a shell profile.

Installed via each project's own `install.sh` rather than Homebrew — a Homebrew install
would only be usable by whichever single account owned that prefix, defeating the point of
a shared workstation:

- **Pinned to the release tag, not `main`.** The script is fetched from
  `raw.githubusercontent.com/anchore/<repo>/v<version>/install.sh`, so its content is fixed
  to what that release published, the same trust boundary as `bats.yml` pinning a git tag.
- **Checksum verification comes from the installer itself.** `install.sh` downloads the
  `checksums.txt` published alongside the release and verifies the binary's SHA-256 before
  installing it — no separate Ansible checksum step is needed.
- **Architecture resolution comes from the installer itself.** `install.sh` maps
  `uname -m` to the release asset name internally, so there is no separate arch-mapping var.
- **Version-aware idempotency.** The installed version (parsed from `grype version` /
  `syft version` output) is compared against the pinned version before re-installing.

The unprivileged verification step runs `syft dir:/etc` and `grype dir:/etc` as `nobody`
with `HOME=/tmp`. For grype, this also downloads the vulnerability database into that
throwaway `HOME`, proving the tool can create and use its own per-user cache
(`$HOME/.cache/grype/db` by default) without any root-owned shared path — this needs
network egress and can take a little while on the first run.

Version overrides:

```bash
ansible-playbook misc/grype-syft.yml -e host=ws01 \
  -e grype_syft_tools='[{"name":"grype","version":"0.116.1","repo":"anchore/grype"},{"name":"syft","version":"1.50.0","repo":"anchore/syft"}]'
```

## trivy.yml

Installs [Trivy](https://github.com/aquasecurity/trivy) (vulnerability scanner) from
Aqua Security's own apt repository, `/usr/bin/trivy`, root-owned. There is no per-user
state and nothing to add to a shell profile.

Ubuntu carries no `trivy` package at all, so this adds the vendor's apt repository:

| Path | Contents |
| --- | --- |
| `/usr/share/keyrings/trivy.gpg` | apt signing key, dearmored from Aqua Security's published key |
| `/etc/apt/sources.list.d/trivy.list` | apt repository definition (`signed-by` pinned to the keyring above) |
| `/usr/bin/trivy` | installed by apt |

- **Signing key handled the same way `apt-key` used to.** `apt-key` is deprecated;
  the key is downloaded, dearmored into `/usr/share/keyrings/trivy.gpg`, and referenced
  from the repo line with `signed-by`, which is the currently supported pattern.
- **Version-aware idempotency**, same as `shellcheck.yml`: the pin is compared against
  `dpkg-query`'s exact version string. Aqua's repo happens to publish `trivy` without a
  Debian revision suffix, so this pin is just the upstream version (`0.73.0`).
- **Repository setup is skipped once installed.** The key/repo tasks only run when the
  pinned version isn't already present, so a host that already has the repo configured
  doesn't re-add it every run.

The unprivileged verification step runs `trivy fs --scanners vuln /etc` as `nobody`
under a disk-backed scratch `HOME` (`/var/tmp/trivy-verify`), the same `/var/tmp`
workaround `grype-syft.yml` needed: Trivy's vulnerability database is roughly 100MiB,
too large for a size-capped `/tmp` tmpfs on some hosts. This also proves Trivy can
create and use its own per-user cache (`$HOME/.cache/trivy` by default) with no
root-owned shared path — it needs network egress and can take a little while on the
first run.

Version overrides:

```bash
ansible-playbook misc/trivy.yml -e host=ws01 -e trivy_version=0.73.0
```

## hadolint.yml

Installs [hadolint](https://github.com/hadolint/hadolint) as a single static binary at
`/usr/local/bin/hadolint`, root-owned, mode `0755`. There is no per-user state and
nothing to add to a shell profile.

hadolint has no apt package or vendor repository, so this installs the upstream release
binary directly, following the same pattern as `gomplate.yml`:

- **Checksum verification** from the release's published `checksums.sha256`, resolved at
  run time so that changing `hadolint_version` stays a one-flag change.
- **Architecture from facts.** `ansible_architecture` is mapped to the release asset
  suffix (`x86_64` → `x86_64`, `aarch64` → `arm64`). Unmapped architectures fail with a
  clear message.
- **Version-aware idempotency.** The installed version (parsed from `hadolint --version`
  output) is compared against the pinned version before re-downloading.

The unprivileged verification step pipes `FROM scratch` into `hadolint -` (reading from
stdin) as `nobody`, with `HOME` deliberately left unset, proving hadolint's
zero-configuration path: no `.hadolint.yaml` is discovered or required.

Version overrides:

```bash
ansible-playbook misc/hadolint.yml -e host=ws01 -e hadolint_version=2.15.1
```

## jsonnet.yml

Installs [jsonnet](https://github.com/google/jsonnet) from the Ubuntu apt package,
`/usr/bin/jsonnet`, root-owned. There is no per-user state and nothing to add to a shell
profile.

A plain apt install, pinned by exact dpkg version the same way
[`core/shellcheck.yml`](../core/README.md) is.

The unprivileged verification step pipes the expression `1 + 1` into `jsonnet -` as `nobody`
and checks that the output is `2`.

Version overrides:

```bash
ansible-playbook misc/jsonnet.yml -e host=ws01 -e jsonnet_version=0.20.0+ds-3.3build1
```

## junit2html.yml

Installs [junit2html](https://gitlab.com/inorton/junit2html) via `pipx`, root-owned:

| Path | Contents |
| --- | --- |
| `/opt/pipx` | `PIPX_HOME` — the pipx-managed virtualenv holding junit2html |
| `/usr/local/bin/junit2html` | `PIPX_BIN_DIR` — the app symlink pipx creates |

Runs `pipx` as `root` with `PIPX_HOME`/`PIPX_BIN_DIR` redirected to the root-owned paths
above — the pipx-as-root pattern from `MIGRATION.md`'s install mechanism decision order —
rather than the per-user `~/.local/bin` / `~/.local/pipx` that a plain `pipx install` as
the connecting user would use. There is nothing to add to a shell profile: junit2html is a
plain CLI with no per-user configuration.

- **No `--version` flag.** junit2html has no way to report its own version, so both the
  idempotency check and the post-install verification instead parse `pipx list --short`,
  which prints `junit2html <version>` once installed.
- **Pinned to the current PyPI release**, not a GitHub tag: upstream moved off GitHub to
  GitLab after `v31.0.2`, so later releases (`31.1.4` and newer) have no corresponding
  GitHub tag at all. `pip`/`pipx` verify the downloaded package against the hash PyPI
  publishes in its index as part of every install; there is no separate checksum step to
  add, the same way apt-based playbooks in this directory need none.
- **World-readable install tree.** `mode: 'u=rwX,go=rX'` is applied recursively to
  `/opt/pipx` after install, since pipx's own venv creation is subject to the umask of
  whoever ran it (`root`, in this case).

The unprivileged verification step renders a small sample JUnit XML fixture to HTML and
confirms the output file exists.

Version overrides:

```bash
ansible-playbook misc/junit2html.yml -e host=ws01 -e junit2html_version=31.1.4
```

## kube-score.yml

Installs [kube-score](https://github.com/zegl/kube-score) as a single static binary at
`/usr/local/bin/kube-score`, root-owned, mode `0755`. There is no per-user state and
nothing to add to a shell profile.

- **Checksum verification** from the release's published `checksums.txt`, resolved at run
  time so that changing `kube_score_version` stays a one-flag change.
- **Architecture from facts.** `ansible_architecture` is mapped to the release asset
  suffix (`x86_64` → `amd64`, `aarch64` → `arm64`). Unmapped architectures fail with a
  clear message.
- **Version-aware idempotency.** The installed version (parsed from `kube-score version`
  output) is compared against the pin before re-downloading.

The unprivileged verification step scores a Deployment manifest that deliberately has a
floating `:latest` image tag, no resource limits, and no security context, and checks the
output flags the image tag issue. kube-score exits non-zero whenever it finds `CRITICAL`
issues, which this manifest is written to trigger — that non-zero exit is the expected,
successful outcome of the check, not a failure of the playbook run.

Version overrides:

```bash
ansible-playbook misc/kube-score.yml -e host=ws01 -e kube_score_version=1.20.0
```

## plantuml.yml

Installs [PlantUML](https://plantuml.com/) from the Ubuntu apt package, `/usr/bin/plantuml`,
root-owned. There is no per-user state and nothing to add to a shell profile.

A plain apt install, pinned by exact dpkg version the same way [`jsonnet.yml`](#jsonnetyml)
and [`core/shellcheck.yml`](../core/README.md) are — including the epoch prefix (`1:`) apt
carries in this package's version string.

The unprivileged verification step pipes a two-line sequence diagram into
`plantuml -pipe -tsvg` as `nobody` and checks the output contains `<svg`. A sequence diagram
only exercises the bundled Java renderer, not the `Recommends`-only `graphviz` dependency
(needed for activity/state diagrams), so this proves the zero-configuration path.

Version overrides:

```bash
ansible-playbook misc/plantuml.yml -e host=ws01 -e plantuml_version=1:1.2020.2+ds-6build1
```

## k6.yml

Installs [k6](https://k6.io/) (load testing tool) from Grafana's own apt repository,
`/usr/bin/k6`, root-owned. There is no per-user state and nothing to add to a shell profile.

Ubuntu carries no `k6` package at all, so this adds the vendor's apt repository, the same
pattern as [`trivy.yml`](#trivyyml):

| Path | Contents |
| --- | --- |
| `/usr/share/keyrings/k6-archive-keyring.gpg` | apt signing key, dearmored from Grafana's published key |
| `/etc/apt/sources.list.d/k6.list` | apt repository definition (`signed-by` pinned to the keyring above) |
| `/usr/bin/k6` | installed by apt |

- **Signing key and repository setup follow `trivy.yml`** exactly: the key is dearmored
  into a dedicated keyring and referenced from the repo line with `signed-by`, and the
  key/repo tasks only run when the pinned version isn't already present.
- **amd64 only.** Grafana's apt repository publishes amd64 packages exclusively (no arm64
  build), so this playbook fails with a clear message on any other architecture rather than
  letting apt report a confusing "no candidate" error.
- **Version-aware idempotency**, same as `trivy.yml`: the pin is compared against
  `dpkg-query`'s exact version string, which k6's repo publishes without a Debian revision
  suffix.

The unprivileged verification step writes a trivial script (a single always-true `check()`,
no HTTP calls) and runs it with `k6 run` as `nobody`, with `K6_NO_USAGE_REPORT=true` so the
run stays fully offline — proving the zero-configuration path the same way
`hadolint.yml`'s stdin check does, without needing a disk-backed scratch directory the way
`trivy.yml` and `grype-syft.yml` do for their vulnerability databases.

Version overrides:

```bash
ansible-playbook misc/k6.yml -e host=ws01 -e k6_version=2.2.0
```

## playwright.yml

Installs [Playwright](https://playwright.dev/) via `npm install -g`, root-owned, the same
mechanism `core/markdownlint.yml` uses for a global npm install. Node.js itself is a
prerequisite provisioned elsewhere; this playbook only checks for it, following
`markdownlint.yml`'s Node-in-PATH guard.

| Path | Contents |
| --- | --- |
| `<npm prefix>/bin/playwright` | npm's bin symlink |
| `<npm prefix>/lib/node_modules/playwright` | the npm package |
| `/opt/playwright-browsers` | shared browser binaries (Chromium by default) |

**Browser binaries are the part a plain npm install doesn't solve.** By default
`playwright install` caches browsers under the invoking account's own
`$HOME/.cache/ms-playwright` — per-user, so every account on the host would separately
re-download several hundred MiB the first time it ran a test. `PLAYWRIGHT_BROWSERS_PATH`
redirects that cache to the shared `/opt` path instead:

- **Published to `/etc/environment`** for real login/SSH sessions, the same
  `lineinfile` pattern `bats.yml`'s `BATS_LIB_PATH` uses — and passed explicitly as task
  `environment` wherever this playbook itself invokes `playwright`, since neither `become`
  nor `setpriv` sources `/etc/environment`.
- **Chromium only by default**, to keep the download and disk footprint reasonable
  (~300MiB). Override `playwright_browsers` to add `firefox` and/or `webkit`.
- **`install --with-deps`** apt-installs the OS libraries each browser needs to run
  headless in the same command that downloads it. This needs to run as root on Linux —
  satisfied here because the whole play already runs under `become`.
- **The browser install step runs unconditionally**, not gated behind the npm package's
  own version check: `playwright install` is already idempotent (it skips any revision
  already present at `PLAYWRIGHT_BROWSERS_PATH`), and gating it on the npm package's
  idempotency check alone would miss a browsers directory that was wiped or never
  populated on an otherwise up-to-date host.

The unprivileged verification step screenshots a `data:` URL — not a real website — as
`nobody`, proving the installed browser and the shared `PLAYWRIGHT_BROWSERS_PATH` cache
both work end to end without depending on outbound network access at verification time,
the same offline-smoke-test approach `hadolint.yml` and `k6.yml` use.

Version overrides:

```bash
ansible-playbook misc/playwright.yml -e host=ws01 -e playwright_version=1.62.1
ansible-playbook misc/playwright.yml -e host=ws01 -e playwright_browsers='["chromium","firefox","webkit"]'
```

## mocha-chai.yml

Installs [Mocha](https://mochajs.org/) (test runner) and [Chai](https://www.chaijs.com/)
(assertion library) via `npm install -g`, root-owned — the same mechanism
`core/markdownlint.yml` uses. Node.js itself is a prerequisite provisioned elsewhere; this
playbook only checks for it.

| Path | Contents |
| --- | --- |
| `<npm prefix>/bin/mocha` | npm's bin symlink — Mocha has a CLI |
| `<npm prefix>/lib/node_modules/mocha` | the npm package |
| `<npm prefix>/lib/node_modules/chai` | the npm package — Chai has **no** CLI |

**Chai is a pure library, which is a new problem for this directory.** Every other
`misc/` npm-based playbook installs a CLI binary onto `PATH` and stops there. Chai has no
binary at all — a test file needs `require('chai')` to resolve, and Node's module
resolution does not search the global npm prefix by default. The fix is `NODE_PATH`:

- **Published to `/etc/environment`**, the same `lineinfile` shape `bats.yml`'s
  `BATS_LIB_PATH` and `playwright.yml`'s `PLAYWRIGHT_BROWSERS_PATH` use, and passed
  explicitly wherever this playbook itself invokes `mocha`, since neither `become` nor
  `setpriv` sources `/etc/environment`.
- **Points at the global `node_modules` directory itself**, not anything mocha/chai
  specific — the same shared location already holding markdownlint-cli, playwright, yarn
  and pnpm. Any other playbook that sets the same `NODE_PATH` line is a no-op, not a
  conflict.

**Chai 6.x ships as ESM-only** (`"type": "module"` in its `package.json`, no CommonJS
entry point), yet plain `require('chai')` from a `.js` test file still works with no extra
configuration — confirmed live on this host's Node.js 24.19.0, which supports requiring an
ESM module directly (Node 22.12+/20.19+ — see `core/nodejs.yml`). Older Node would need
`import()` or a `.mjs` test file instead.

**Version-aware idempotency checks mocha and chai separately** — one `npm ls -g
<name>@<version>` call per package — rather than a single combined
`npm ls -g mocha@x chai@y`. Confirmed live: `npm ls -g`'s exit code is 0 as soon as *any
one* of several `name@version` arguments matches something installed; it is not an AND
across arguments, so a single combined call cannot tell "both pinned" apart from "only one
of them is."

The unprivileged verification step writes a spec file that asserts with Chai
(`expect(1 + 1).to.equal(2)`) and runs it with `mocha` as `nobody`, checking for `1
passing` in the output — proving the installed binary, the version pin, and the shared
`NODE_PATH` resolution of Chai all work together for an account that did no setup of its
own.

Version overrides:

```bash
ansible-playbook misc/mocha-chai.yml -e host=ws01 \
  -e mocha_chai_packages='[{"name":"mocha","version":"11.8.0"},{"name":"chai","version":"6.2.2"}]'
```

## maven.yml

Installs [Apache Maven](https://maven.apache.org/) from the Apache binary distribution,
root-owned, with a versioned tree and a symlink — the `cloud-cli/influx-cli.yml` shape, so
`ls -l /usr/local/bin/mvn` says which version is active and a bump installs beside the old
tree.

| Path | Contents |
| --- | --- |
| `/usr/local/lib/maven/<version>/` | the unpacked distribution |
| `/usr/local/bin/mvn` | symlink to that version's `bin/mvn` |

A JDK (`default-jdk-headless`) is installed as a prerequisite, unpinned — the same way
`cloud-cli/jenkins-cli.yml` installs the JRE it needs. Nothing is written to any `$HOME`:
each account gets its own `~/.m2` (local artifact repository, and optionally a personal
`settings.xml` holding repository credentials) the first time it runs a build, which is
exactly the per-user state a shared workstation should keep per-user.

**Not the apt package, deliberately.** Ubuntu 26.04 carries `maven` 3.9.12-1, four patch
releases behind the 3.9.16 pinned here; the Apache tarball is self-contained, checksum-
verified, and the version this repo pins is the version installed. Maven 4.0.0 and 3.10.0
are both still release candidates as of 2026-08-17, so the 3.9.x line is the stable choice.

### How the install is put together

- **Integrity and idempotency.** The tarball is fetched with `get_url` against Apache's
  published `.sha512`, and the whole install is skipped when the pinned version is already
  active rather than re-downloaded every run.
- **The tarball, not the zip.** Apache's `-bin.zip` does not carry Unix permission bits
  reliably; the `.tar.gz` does, and its `bin/mvn` arrives already `0755`.
- **No `settings.xml` of this repo's own.** The distribution ships one and it is left exactly
  as shipped — writing a copy here to configure nothing is the dead config MIGRATION2's A2/A3
  removed elsewhere. A host that needs a proxy or a mirror sets it there or in each account's
  own `~/.m2/settings.xml`.
- **A declared JDK prerequisite** rather than an assumption that something else installed one.

### The JVM reads `user.home` from the passwd database, not `$HOME`

`HOME=<scratch> java -XshowSettings:properties` prints `user.home = /nonexistent` for uid
65534, so Maven tries to create `/nonexistent/.m2/repository` and fails no matter how
carefully `$HOME` is set — the same class of trap as `core/ansible-core.yml`'s `remote_tmp`.
The unprivileged checks therefore pass an explicit `-Dmaven.repo.local`. They also need
`chdir`: the `mvn` script walks up looking for a project base directory, and an unprivileged
process left in a directory it cannot read prints `cd: can't cd to /home/<invoker>` — the
defect MIGRATION2 found in `gcx-cli.yml`, here triggered by Maven's own launcher.

### The smoke test is an offline build, plus a deliberate failure

`mvn -o -B validate` on a generated project must reach `BUILD SUCCESS` with an **empty**
local repository and no network at all — proving Maven resolved the super POM, the lifecycle
mapping and the project model out of the installed distribution. A second run against the
same POM with `<version>` removed must fail with `'version' is missing`: without that
negative half, a Maven that parsed nothing would still have reported success.

Version overrides:

```bash
ansible-playbook misc/maven.yml -e host=ws01 -e maven_version=3.9.16
```

## testssl.yml

Installs [testssl.sh](https://testssl.sh/), the TLS/SSL scanner, from its upstream git tree —
versioned directory plus a symlink, the same shape as [`maven.yml`](#mavenyml).

| Path | Contents |
| --- | --- |
| `/usr/local/lib/testssl.sh/<version>/` | the upstream tree: script, `etc/` data files, bundled OpenSSL |
| `/usr/local/bin/testssl.sh` | symlink to that version's script |

testssl.sh is not a single binary — it reads its cipher mappings and CA bundles from `etc/`
and prefers the OpenSSL build in `bin/`, both resolved relative to the script's own location.
So the whole tree is installed and only the entry point goes on `PATH`; confirmed live that
invoking it through the symlink, from a directory the caller cannot read, still finds both.
No per-user state, nothing in a shell profile: scans write where the caller asks
(`--htmlfile`, `--jsonfile`) and temporary files to `$TMPDIR`.

**Not the apt package, deliberately.** apt carries `testssl.sh` 3.2.2+dfsg-1, and the `+dfsg`
repack exists precisely because it strips the bundled OpenSSL binaries — the build testssl.sh's
own output calls *"OpenSSL 1.0.2-bad"*, kept deliberately broken so it still speaks SSLv2,
SSLv3 and export ciphers. This host's OpenSSL is 3.5.5, which refuses all of them, so the
stripped package cannot detect the weak protocols the scanner exists to find.

### What is pinned is a tag *and* a commit

Checking out a branch — or even a tag by name alone — installs whatever it points at on the
day and records nothing about what that was. This pins the `v3.2.4` tag **and** the commit that
tag pointed at when the pin was taken, since tags are mutable on GitHub and commit ids are not.
The commit is re-checked on **every** run, not just at install time, so a moved tag or an
edited tree is caught rather than silently inherited.

The versioned directory plus symlink is also what makes `depth: 1` safe: a per-version
directory is never re-pointed at another tag, which is the thing shallow clones make awkward
(`bats.yml` clones in full for exactly that reason). Worth having here — 22 MB against 145 MB
of history.

### The smoke test scans a real TLS endpoint

An `openssl s_server` with a throwaway certificate is started on `127.0.0.1`, scanned by uid
65534 through the published symlink, and killed by a trap whatever happens. Both directions are
asserted — TLS 1.2 reported as **offered** and SSLv2 as **not offered** — so neither a
testssl.sh that printed a fixed table nor one that never reached the server can pass. About six
seconds; `--protocols` keeps it to the protocol section rather than a full scan.

One quirk worth knowing if you touch the version check: `--version` must be the *only* option
on the command line (`Fatal error: --version is a standalone command line option`), so colours
cannot be disabled with `--color 0` and are stripped with `sed` instead. Its first line names
the program *as invoked* — through a differently-named symlink it prints that name — so the
assertion anchors on `version <x> from https://testssl.sh/`, never on the program name.

Version overrides — bump the tag and the commit together:

```bash
git ls-remote https://github.com/testssl/testssl.sh.git 'refs/tags/v3.2.4^{}'
ansible-playbook misc/testssl.yml -e host=ws01 -e testssl_version=3.2.4 -e testssl_commit=<sha>
```

## zap.yml

Installs [OWASP ZAP](https://www.zaproxy.org/) from the upstream release tarball into a
versioned tree with a symlink, the same shape as [`maven.yml`](#mavenyml) and
[`testssl.yml`](#testsslyml).

| Path | Contents |
| --- | --- |
| `/usr/local/lib/zap/<version>/` | the distribution — jars, add-ons, language packs (~270 MB) |
| `/usr/local/bin/zap.sh` | symlink to that version's launcher |

ZAP is a tree, not a binary: `zap.sh` resolves everything else relative to its own location, so
the whole distribution is installed and only the launcher goes on `PATH` — confirmed that
invoking it through the symlink works, which is why nothing here touches `PATH` in
`/etc/environment`. `default-jre` is a prerequisite rather than the `-headless` variant every
other Java playbook here installs: ZAP with no arguments *is* its desktop UI, which throws
`HeadlessException` on a headless JRE, and on these desktop workstations that is a real use.

### ZAP's "home" is per-user state, and this playbook creates none of it

ZAP keeps configuration, its session database, downloaded add-ons and `zap.log` in `~/.ZAP` —
one directory per account, created on first run. That is exactly the state a shared workstation
must not share: a single world-writable copy would put one account's session history, and any
credentials captured in it, within everyone else's reach.

That makes verification a trap twice over, and both halves were reproduced on a target:

- **The JVM reads `user.home` from the passwd database, not `$HOME`**, so for uid 65534 ZAP
  resolves its home to `/nonexistent` and dies with `Unable to create home directory:
  /nonexistent/.ZAP/` no matter how `$HOME` is set. The scan passes an explicit `-dir`. Same
  trap [`maven.yml`](#mavenyml) documents, but fatal here rather than a fallback.
- **Running `zap.sh` as root without `-dir` creates `/root/.ZAP`**, which MIGRATION3's B2
  forbids. So ZAP is never run as root at all: the install check is filesystem state, and the
  single ZAP invocation in the play is the unprivileged scan.

### One invocation, which is also the version check

`zap.sh -version` costs about 35 seconds — it starts the JVM and initialises every add-on — so
running it as a separate step would only make the play slower. Instead the scan's own JSON
report carries `"@version"`, and that is what the pin is asserted against.

The scan itself is the tool doing its job: a static page is served on `127.0.0.1` by
`python3 -m http.server`, and ZAP crawls and passively scans it as uid 65534 through the
published symlink, writing a JSON report (~25 seconds). Two things are asserted — the report's
version matches the pin, and its site list names the loopback URL, proving ZAP actually reached
and crawled the server rather than reporting on nothing. `-silent` disables ZAP's optional
outbound calls (telemetry, add-on update checks) so the scan talks to nothing but the local
server, and the server is killed by PID from a trap — a pattern kill would match the task's own
command line.

Integrity comes from the SHA-256 GitHub computes per release asset (the
[`core/yq.yml`](../core/README.md#yqyml) source), since ZAP publishes no checksums file beside
the tarball.

Version overrides:

```bash
ansible-playbook misc/zap.yml -e host=ws01 -e zap_version=2.17.0
```

## mongodb-tools.yml

Installs the MongoDB client tooling: the [Database Tools](https://www.mongodb.com/docs/database-tools/)
and the [MongoDB Shell](https://www.mongodb.com/docs/mongodb-shell/). Clients only — no `mongod`,
nothing listening.

| Path | Contents |
| --- | --- |
| `/usr/bin/bsondump`, `mongodump`, `mongorestore`, `mongoexport`, `mongoimport`, `mongofiles`, `mongostat`, `mongotop` | `mongodb-database-tools`, from MongoDB's apt repository |
| `/usr/bin/mongosh`, `/usr/lib/mongosh_crypt_v1.so` | `mongodb-mongosh`, from its own release `.deb` |
| `/etc/apt/sources.list.d/mongodb.sources` | repository definition, key by URL, fingerprint pinned |

No per-user setup: mongosh creates `~/.mongodb/mongosh` (config, history, logs) for each account
on first use, which is per-account state a shared workstation should keep per-account. Nothing
here writes into anyone's `$HOME` — a plain `mongosh --version` writes nothing, checked with a
fresh `HOME`, which is why the version check can stay a `dpkg-query`.

### The 26.04 build of the Database Tools does not run on this repo's hosts

This is why the repository points at **`noble`** (24.04) rather than this release's own
`resolute`. MongoDB's resolute build of `mongodb-database-tools` 100.18.0 declares:

```
x86 ISA needed: x86-64-baseline, x86-64-v2, x86-64-v3
```

and every binary in it dies with `CPU ISA level is lower than required` on ws01 (Core i7-3615QM,
Ivy Bridge) and ws02 (Core i5-2520M, Sandy Bridge) — neither CPU has the AVX2-era instructions
`x86-64-v3` needs. MongoDB's noble build of the *identical* 100.18.0 is `x86-64-baseline`, runs on
both, is byte-for-byte the same file as the `ubuntu2404` package on `fastdl.mongodb.org` (same
SHA-256), and depends only on `libc6` and the krb5 libraries, all present on 26.04. Set
`mongodb_tools_release` to `resolute` once MongoDB ships a baseline build there, or on a fleet
that is uniformly `x86-64-v3`.

Note that MongoDB folds the server release series into the apt **suite**, not the component:
the sources line is `<release>/mongodb-org/<series> multiverse`, and apt fetches
`dists/noble/mongodb-org/8.0/InRelease`. Series 8.0 is used because it is the one whose signing
key MongoDB publishes — `server-9.0.asc` is a 404 at both of MongoDB's key URLs as of
2026-08-17 — and `mongodb-database-tools` is identical in both series.

### The package installs its binaries owned by uid 1000

`dpkg-deb -c` on MongoDB's `.deb` shows every file recorded as `ubuntu/ubuntu`, uid and gid
1000, and dpkg honours that: a plain install leaves `/usr/bin/mongodump` and its seven siblings
owned by whoever is uid 1000 on the host. On these workstations that is a real login account,
which would then be free to rewrite binaries every other account runs — and that root runs too,
under `sudo`. The playbook corrects ownership to `root:root` on **every** run, not only after an
install, so a host that already took the package the plain way is repaired as well. The
closing assertion that every tool is a root-owned executable is not a formality here: without
that fix, it fails.

### mongosh comes from its release `.deb`, not from apt

mongosh is not in the resolute repository at all, and the only suite that carries it
(`noble/mongodb-org/9.0`) is signed by the unpublished 9.0 key, so that repository's key cannot
be pinned. The `.deb` attached to mongosh's own GitHub release is used instead, verified against
the SHA-256 GitHub computes per asset — the [`core/yq.yml`](../core/README.md#yqyml) source. The
plain package is the one chosen deliberately: unlike the `shared-openssl11`/`shared-openssl3`
variants it bundles its own OpenSSL and depends on nothing but `libc6`, which is what makes it
safe to install outside a repository.

### Verification is two pieces of real offline work

- **`bsondump`** decodes a hand-written twelve-byte BSON document (`{"a": 1}`: int32 length,
  element type `0x10`, key `a\0`, value, terminator) written with `printf` and octal escapes,
  since a `copy:` block cannot carry NUL bytes. That exercises the same BSON reader
  `mongorestore` uses, with no server involved.
- **`mongosh --nodb`** evaluates JavaScript with no server to connect to, asserting arithmetic,
  the EJSON serialiser's date encoding, and the version the process reports about itself. It
  runs through `shell` with the expression single-quoted: `command` tokenises shlex-style
  without a shell, which eats the quotes around a JavaScript string literal and splits on the
  spaces inside one — mongosh answers either mistake with a `SyntaxError`.

Version overrides:

```bash
ansible-playbook misc/mongodb-tools.yml -e host=ws01 -e mongodb_tools_version=100.18.0
ansible-playbook misc/mongodb-tools.yml -e host=ws01 -e mongosh_version=2.10.0
```

## certbot.yml

Installs [certbot](https://certbot.eff.org/) and the Route 53 DNS plugin with `pipx`, run as
root with its state redirected to root-owned, world-readable paths — the same shape
[`junit2html.yml`](#junit2htmlyml) uses.

| Path | Contents |
| --- | --- |
| `/opt/pipx/venvs/certbot/` | the virtualenv: certbot and every injected plugin |
| `/usr/local/bin/certbot` | the app symlink pipx creates |
| `/usr/local/share/man/` | `PIPX_MAN_DIR` — see below |

The client only. Nothing here obtains, renews or installs a certificate, and no ACME account is
registered for anyone: those need real DNS or a real web server and are run by hand under
`sudo`. certbot's own state lives in `/etc/letsencrypt`, `/var/lib/letsencrypt` and
`/var/log/letsencrypt` — root-owned system paths, not per-user state — and none of the three is
created here.

### pipx, not apt and not snap

- **apt** carries certbot `4.0.0-4` on 26.04 against upstream's `5.7.0` — a whole major version
  behind. certbot speaks ACME to a live CA, and that gap is exactly where its protocol-level
  fixes sit, so this is one of the tools worth taking from upstream.
- **snap** installs cleanly, but it refreshes on Canonical's schedule rather than on a pin in
  this repository, which is the opposite of what every other playbook here does. Nothing else
  in `playbooks/` uses snap.

### `PIPX_MAN_DIR` is set deliberately

Without it, pipx creates `/root/.local/share/man`. Confirmed by experiment: remove that
directory, run an install with `PIPX_MAN_DIR` set — it stays gone and the configured directory
appears instead — then run one without it, and it comes back. Writing under root's own `$HOME`
is what MIGRATION3's B2 forbids, and it also puts any man page a package ships somewhere no
other account can read. Here it points at `/usr/local/share/man`, where `man certbot` finds it.

The playbook also clears up the directory earlier runs left behind, with `rmdir` rather than
`state: absent` so it goes only when empty: anything since put there is somebody's and is left
alone.

### The plugin is injected, not installed alongside

certbot discovers plugins through the `certbot.plugins` entry point group **inside its own
virtualenv**, so a separate `pipx install certbot-dns-route53` would leave `certbot plugins`
unchanged. `pipx inject` puts the plugin in the same venv, which is what makes it loadable.
Idempotency reads `pipx list --json` — the `--short` form names only the main package, and this
playbook has to compare injected plugin versions too — and only injects what is missing or at
the wrong version.

Adding another plugin is one list entry (`certbot_plugins`); it is injected and then verified
the same way.

### Verification lists the plugins as an unprivileged user

`certbot plugins` enumerates the entry points certbot can actually load, so a plugin appearing
there is one certbot could really use. The assertion requires the pinned plugins **and**
certbot's own `standalone`/`webroot` authenticators, so a truncated or empty listing cannot
pass. certbot insists on writable config, work and log directories even for read-only
subcommands, and its real ones are root-only by design, so the check points all three at a
scratch directory it removes afterwards.

One quirk: task 11 (the recursive mode fix on the pipx tree) reports `changed` under `--check`
while reporting nothing on a real run — with `recurse`, the `file` module cannot walk a tree it
is not allowed to touch and answers conservatively.

Version overrides — plugins track `certbot_version` unless pinned individually:

```bash
ansible-playbook misc/certbot.yml -e host=ws01 -e certbot_version=5.7.0
```
