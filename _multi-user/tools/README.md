# Tool Installation Playbooks (multi-user workstations)

Standalone playbooks that install developer tooling on a **shared** Ubuntu workstation.
They are the multi-user successors to `tool/`, which installs into a single user's
Homebrew prefix and `~/.bashrc` and therefore only serves the account that ran it.

Run from `_multi-user/`:

```bash
ansible-playbook tools/<tool>.yml -e host=<inventory host or group>
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
ansible-playbook tools/bats.yml -e host=ws01 -e bats_core_version=1.13.0
```

## gomplate.yml

Installs [gomplate](https://github.com/hairyhenderson/gomplate) as a single static binary
at `/usr/local/bin/gomplate`, root-owned, mode `0755`. There is no per-user state and
nothing to add to a shell profile.

The source playbook already installed system-wide, so the changes here are correctness
rather than multi-user reach:

- **Version-aware idempotency.** The original guarded the download with
  `when: not gomplate_check.stat.exists`, so once the binary existed, bumping
  `gomplate_version` did nothing. The installed version is now compared instead.
- **Checksum verification.** The SHA-256 is read from the release's published
  `checksums-v<version>_sha256.txt` at run time, so changing the version stays a one-flag
  change instead of also requiring a hardcoded hash update.
- **Architecture from facts.** `ansible_architecture` is mapped to the release asset
  suffix (`x86_64` → `amd64`, `aarch64` → `arm64`) rather than assuming amd64. Unmapped
  architectures fail with a clear message.

Version overrides:

```bash
ansible-playbook tools/gomplate.yml -e host=ws01 -e gomplate_version=4.3.3
```

## grype-syft.yml

Installs [grype](https://github.com/anchore/grype) (vulnerability scanner) and
[syft](https://github.com/anchore/syft) (SBOM generator) as single static binaries at
`/usr/local/bin/grype` and `/usr/local/bin/syft`, root-owned, mode `0755`. There is no
per-user state and nothing to add to a shell profile.

The source playbook installed both via Homebrew, which only the account that ran
`core/homebrew.yml` can use. This migration instead uses each project's own `install.sh`:

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
ansible-playbook tools/grype-syft.yml -e host=ws01 \
  -e grype_syft_tools='[{"name":"grype","version":"0.116.1","repo":"anchore/grype"},{"name":"syft","version":"1.50.0","repo":"anchore/syft"}]'
```

## shellcheck.yml

Installs [ShellCheck](https://github.com/koalaman/shellcheck) from the Ubuntu apt
package, `/usr/bin/shellcheck`, root-owned. There is no per-user state and nothing to
add to a shell profile.

The source playbook installed it via Homebrew, which only the account that ran
`core/homebrew.yml` can use. The apt package is current enough to use directly instead:

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
ansible-playbook tools/shellcheck.yml -e host=ws01 -e shellcheck_version=0.9.0-1
```

## trivy.yml

Installs [Trivy](https://github.com/aquasecurity/trivy) (vulnerability scanner) from
Aqua Security's own apt repository, `/usr/bin/trivy`, root-owned. There is no per-user
state and nothing to add to a shell profile.

The source playbook installed it via Homebrew. Ubuntu carries no `trivy` package at
all, so this adds the vendor's apt repository instead:

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
ansible-playbook tools/trivy.yml -e host=ws01 -e trivy_version=0.73.0
```

## hadolint.yml

Installs [hadolint](https://github.com/hadolint/hadolint) as a single static binary at
`/usr/local/bin/hadolint`, root-owned, mode `0755`. There is no per-user state and
nothing to add to a shell profile.

The source playbook installed it via Homebrew. hadolint has no apt package or vendor
repository, so this migration uses the upstream release binary directly, following the
same pattern as `gomplate.yml`:

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
ansible-playbook tools/hadolint.yml -e host=ws01 -e hadolint_version=2.15.1
```

## modern-cli-tools.yml

Installs 14 modern CLI tool replacements from apt, root-owned, at `/usr/bin` (no per-user
state, nothing added to a shell profile for any of them):

| Tool | apt package | Binary |
| --- | --- | --- |
| gum, fzf, jq, jsonnet, eza, lsd, duf, procs, gdu, htop, glow | same name | same name |
| ripgrep | `ripgrep` | `rg` |
| bat | `bat` | `batcat` (symlinked to `/usr/local/bin/bat`) |
| dust | `du-dust` | `dust` |

Also lays down:

| Path | Contents |
| --- | --- |
| `/etc/profile.d/fzf.sh` | `eval "$(fzf --bash)"` — fzf key bindings and completion |

The source playbook installed 16 tools (including `yq` and `llhttp`, a manual dependency
shim; see below) via Homebrew. `yq` is split out to its own `yq.yml`, since it is the one
tool in this bundle that is not a plain apt install. Migrating the rest uncovered two real
differences from the plan in `MIGRATION.md`, both only visible by checking the actual target
host rather than assuming:

- **No Charm apt repo needed.** The plan called for Aqua-style vendor apt repo for `gum` and
  `glow`, on the assumption Ubuntu's own repos lagged. On the actual target (Ubuntu 26.04
  "resolute"), apt already carries both directly (`gum` 0.17.0-1, `glow` 2.1.1-1) — one apt
  install covers all 14 tools, no vendor repo at all.
- **`llhttp` is dropped entirely**, not migrated. The source playbook symlinked a Homebrew
  Cellar path (`libllhttp.so.9.3`) so its Homebrew-built `eza` could find the library at
  runtime — a Homebrew Cellar-isolation workaround. apt's `eza` package declares
  `libgit2-1.9` etc. as proper package dependencies, so nothing extra is needed.

fzf's key bindings need `/etc/profile.d` to actually be read by interactive shells, which is
not true by default for a non-login shell (e.g. a plain SSH session) on stock Ubuntu — see
"Known follow-ups" in `MIGRATION.md`. This playbook adds that hook to `/etc/bash.bashrc`,
since fzf is the first migrated tool that needs it; the task is an idempotent no-op for any
later playbook (`vault.yml`) that adds the same hook.

The unprivileged verification step runs every tool's `--version` as `nobody`, then separately
opens a non-login interactive `bash -i` shell as the same user and checks that fzf's
`__fzf_select__` function is defined — proving the `/etc/profile.d` → `/etc/bash.bashrc` chain
actually works end-to-end for a real interactive session, not just that the binaries exist.

apt package pins are release-specific (see `shellcheck.yml`'s note on the same issue); to
override one, edit `modern_cli_tools_packages` with `-e` as a JSON list, the same pattern
`grype-syft.yml` uses for its tool list.

## yq.yml

Installs [mikefarah/yq](https://github.com/mikefarah/yq) as a single static binary at
`/usr/local/bin/yq`, root-owned, mode `0755`. There is no per-user state and nothing to add
to a shell profile.

Split out from `modern-cli-tools.yml` rather than bundled with it, since it is the one tool
in that source playbook that is not a plain apt install: per the decision-order gotcha in
`MIGRATION.md`, Ubuntu's apt `yq` is `kislyuk/yq`, a Python wrapper around `jq` with entirely
different syntax from mikefarah's Go `yq` that Homebrew's `yq` formula installs. Silently
swapping one for the other under the same command name would break any script written
against the Go one, so this installs the real thing as a release binary instead.

- **Checksum verification, but not from a checksums file.** yq's own published checksums file
  uses a bespoke multi-algorithm rhash table (`checksums_hashes_order` /
  `extract-checksum.sh` in the release), not the plain `hash  filename` format
  `gomplate.yml`/`hadolint.yml` parse. Instead, the playbook reads the SHA-256 `digest`
  GitHub computes and serves per release asset via its own releases API — simpler to consume
  and just as authoritative.
- **Architecture from facts.** `ansible_architecture` is mapped to the release asset suffix
  (`x86_64` → `amd64`, `aarch64` → `arm64`). Unmapped architectures fail with a clear message.
- **Version-aware idempotency.** The installed version (parsed from `yq --version` output) is
  compared against the pinned version before re-downloading.

The unprivileged verification step pipes `a: 1` into `yq e '.a' -` (reading from stdin) as
`nobody` and checks the output, proving yq's zero-configuration path.

Version overrides:

```bash
ansible-playbook tools/yq.yml -e host=ws01 -e yq_version=4.53.3
```

## junit2html.yml

Installs [junit2html](https://gitlab.com/inorton/junit2html) via `pipx`, root-owned:

| Path | Contents |
| --- | --- |
| `/opt/pipx` | `PIPX_HOME` — the pipx-managed virtualenv holding junit2html |
| `/usr/local/bin/junit2html` | `PIPX_BIN_DIR` — the app symlink pipx creates |

The source playbook ran `pipx install` as the connecting user, which lands in that user's
own `~/.local/bin` and `~/.local/pipx`; only that account can then run `junit2html`. This
migration instead runs `pipx` as `root` with `PIPX_HOME`/`PIPX_BIN_DIR` redirected to the
root-owned paths above, following the pipx-as-root pattern from `MIGRATION.md`'s install
mechanism decision order. There is nothing to add to a shell profile: junit2html is a
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
ansible-playbook tools/junit2html.yml -e host=ws01 -e junit2html_version=31.1.4
```

## kube-score.yml

Installs [kube-score](https://github.com/zegl/kube-score) as a single static binary at
`/usr/local/bin/kube-score`, root-owned, mode `0755`. There is no per-user state and
nothing to add to a shell profile.

The source playbook already installed to this same root-owned path — like `gomplate.yml`,
this migration is correctness work rather than reach work:

- **Checksum verification** from the release's published `checksums.txt`, resolved at run
  time so that changing `kube_score_version` stays a one-flag change.
- **Architecture from facts.** `ansible_architecture` is mapped to the release asset
  suffix (`x86_64` → `amd64`, `aarch64` → `arm64`). Unmapped architectures fail with a
  clear message.
- **Version-aware idempotency.** The original guarded the download with
  `stat.exists`, so once the binary existed, bumping `kube_score_version` did nothing. The
  installed version (parsed from `kube-score version` output) is now compared instead.

The unprivileged verification step scores a Deployment manifest that deliberately has a
floating `:latest` image tag, no resource limits, and no security context, and checks the
output flags the image tag issue. kube-score exits non-zero whenever it finds `CRITICAL`
issues, which this manifest is written to trigger — that non-zero exit is the expected,
successful outcome of the check, not a failure of the playbook run.

Version overrides:

```bash
ansible-playbook tools/kube-score.yml -e host=ws01 -e kube_score_version=1.20.0
```

## markdownlint.yml

Installs [markdownlint-cli](https://github.com/igorshubovych/markdownlint-cli) via
`npm install -g`, root-owned. Node.js itself is a prerequisite provisioned elsewhere; this
playbook only checks for it, and fails loudly with setup instructions if it is missing.

The source playbook already installed via `npm install -g` with `become`, so nothing
needed to move — this migration is correctness work, not reach work:

- **Pinned version.** The source playbook installed `markdownlint-cli@latest`.
- **Version-aware idempotency.** The source playbook only checked for the binary's
  presence (`which markdownlint`); the installed version is now compared instead.
- **npm's global prefix is read at run time, not assumed.** `npm config get prefix`
  turned out to disagree between the two hosts this was verified against: a
  NodeSource-installed Node.js defaults it to `/usr` (`/usr/lib/node_modules`,
  `/usr/bin/markdownlint`), while Ubuntu's own `nodejs` apt package defaults it to
  `/usr/local` (`/usr/local/lib/node_modules`, `/usr/local/bin/markdownlint`). Both are
  root-owned system paths, so either is fine — but hardcoding one breaks the other.
- **Node-in-PATH guard kept from the source playbook**, broadened to accept either system
  prefix: fails if `which node` resolves outside `/usr/bin/node` or `/usr/local/bin/node`,
  which would indicate a per-user version manager (nvm, fnm, ...) shadowing the system
  Node.js for the connecting account.

The unprivileged verification step lints a Markdown file with a deliberate heading-space
issue and checks the output for that specific rule (`MD018`). markdownlint writes its
findings to **stderr**, not stdout, and exits non-zero when it finds issues — both are the
expected, successful outcome of this check, not a failure of the playbook run.

Version overrides:

```bash
ansible-playbook tools/markdownlint.yml -e host=ws01 -e markdownlint_cli_version=0.49.1
```
