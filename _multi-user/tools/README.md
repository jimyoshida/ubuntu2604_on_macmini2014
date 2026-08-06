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

Installs 15 modern CLI tool replacements. 14 come from apt, root-owned, at `/usr/bin` (no
per-user state, nothing added to a shell profile for any of them):

| Tool | apt package | Binary |
| --- | --- | --- |
| gum, fzf, jq, jsonnet, eza, lsd, duf, procs, gdu, htop, glow | same name | same name |
| ripgrep | `ripgrep` | `rg` |
| bat | `bat` | `batcat` (symlinked to `/usr/local/bin/bat`) |
| dust | `du-dust` | `dust` |

The fifteenth, **yq**, is the one tool in this bundle that is not a plain apt install:

| Path | Contents |
| --- | --- |
| `/usr/local/bin/yq` | [mikefarah/yq](https://github.com/mikefarah/yq) release binary |
| `/etc/profile.d/fzf.sh` | `eval "$(fzf --bash)"` — fzf key bindings and completion |

The source playbook installed all 16 (including `llhttp`, a manual dependency shim; see
below) via Homebrew. Migrating this one uncovered three real differences from the plan in
`MIGRATION.md`, all only visible by checking the actual target host rather than assuming:

- **No Charm apt repo needed.** The plan called for Aqua-style vendor apt repo for `gum` and
  `glow`, on the assumption Ubuntu's own repos lagged. On the actual target (Ubuntu 26.04
  "resolute"), apt already carries both directly (`gum` 0.17.0-1, `glow` 2.1.1-1) — one apt
  install covers all 14 non-yq tools, no vendor repo at all.
- **`llhttp` is dropped entirely**, not migrated. The source playbook symlinked a Homebrew
  Cellar path (`libllhttp.so.9.3`) so its Homebrew-built `eza` could find the library at
  runtime — a Homebrew Cellar-isolation workaround. apt's `eza` package declares
  `libgit2-1.9` etc. as proper package dependencies, so nothing extra is needed.
- **`yq` is a deliberate exception to "prefer apt".** Per the decision-order gotcha in
  `MIGRATION.md`: Ubuntu's apt `yq` is `kislyuk/yq`, a Python wrapper around `jq` with
  entirely different syntax from mikefarah's Go `yq` that Homebrew's `yq` formula installs.
  Silently swapping one for the other under the same command name would break any script
  written against the Go one, so this installs the real thing as a release binary instead.
  Its own published checksums file uses a bespoke multi-algorithm rhash table
  (`checksums_hashes_order` / `extract-checksum.sh` in the release), not the plain
  `hash  filename` format `gomplate.yml`/`hadolint.yml` parse. Instead, the playbook reads
  the SHA-256 `digest` GitHub computes and serves per release asset via its own API — simpler
  to consume and just as authoritative.

fzf's key bindings need `/etc/profile.d` to actually be read by interactive shells, which is
not true by default for a non-login shell (e.g. a plain SSH session) on stock Ubuntu — see
"Known follow-ups" in `MIGRATION.md`. This playbook adds that hook to `/etc/bash.bashrc`,
since fzf is the first migrated tool that needs it; the task is an idempotent no-op for any
later playbook (`vault.yml`) that adds the same hook.

The unprivileged verification step runs every tool's `--version` as `nobody`, then separately
opens a non-login interactive `bash -i` shell as the same user and checks that fzf's
`__fzf_select__` function is defined — proving the `/etc/profile.d` → `/etc/bash.bashrc` chain
actually works end-to-end for a real interactive session, not just that the binaries exist.

Version overrides:

```bash
ansible-playbook tools/modern-cli-tools.yml -e host=ws01 -e modern_cli_tools_yq_version=4.53.3
```

apt package pins are release-specific (see `shellcheck.yml`'s note on the same issue); to
override one, edit `modern_cli_tools_packages` with `-e` as a JSON list, the same pattern
`grype-syft.yml` uses for its tool list.
