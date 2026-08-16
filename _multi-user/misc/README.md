# Misc Playbooks (multi-user workstations)

Standalone playbooks that install developer tooling on a **shared** Ubuntu workstation, to
root-owned system paths usable by every account on the host rather than into one account's
home directory.

Run from `_multi-user/`:

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
