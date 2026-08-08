# Cloud CLI Playbooks (multi-user workstations)

Standalone playbooks that install cloud and service CLI tools on a **shared** Ubuntu
workstation. They are the multi-user successors to `cloud-cli/`. See
[MIGRATION2.md](../../MIGRATION2.md) for the policy and the per-tool plan.

Run from `_multi-user/`:

```bash
ansible-playbook cloud-cli/<tool>.yml -e host=<inventory host or group>
```

## Conventions

These playbooks follow the same rules as [`tools/`](../tools/README.md) — root-owned
system paths, no Homebrew, no writes to any `$HOME`, pinned versions, and a closing check
that runs the tool as an arbitrary uid (`setpriv --reuid=65534`) rather than as the
connecting user. Three rules matter specifically here, because every tool in this
directory carries an identity:

1. **The binary is shared; the identity is not.** Playbooks install the client and stop.
   They never run `aws configure`, `gcloud auth login`, `az devops configure`, or any
   other per-person setup — each account does that for itself, and the commands to run
   are printed by each playbook's closing summary.
2. **Secrets never leave `$HOME`.** Non-secret endpoint configuration (a default server
   URL, an organization name) may go to `/etc/environment` when it is genuinely shared.
   Tokens, PATs, and keys never do: `/etc/environment` is world-readable, and a shared
   workstation is exactly where that matters.
3. **Verification proves reachability, not authentication.** These tools cannot do real
   work unauthenticated, so the unprivileged check asserts that an arbitrary uid can
   execute the binary, load its libraries, and reach its own zero-configuration code
   path — with discovery variables left unset so that default discovery is what gets
   tested.

## aws-cli.yml

Installs the [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/) from AWS's
official installer.

| Path | Contents |
| --- | --- |
| `/usr/local/aws-cli/v2/<version>/` | bundled Python interpreter and libraries |
| `/usr/local/aws-cli/v2/current` | symlink to the active version |
| `/usr/local/bin/aws` | executable (symlink into the tree above) |
| `/usr/local/bin/aws_completer` | shell completion helper (symlink) |

Everything is root-owned and explicitly `u=rwX,go=rX`; the installer applies root's umask
rather than an explicit mode, so the playbook sets it afterwards.

**What changed versus `cloud-cli/aws-cli.yml`.** The mechanism is unchanged — AWS's
installer already targets root-owned system paths, so this was correctness work:

- **The version is pinned** (`aws_cli_version`) and fetched from a versioned URL. The
  source playbook downloaded whatever `awscli-exe-linux-x86_64.zip` currently resolved to.
- **The installer's GPG signature is verified** against AWS's published signing key,
  which is pinned in the playbook. The source playbook verified nothing.
- **The architecture comes from `ansible_architecture`.** The source playbook hardcoded
  `x86_64`, so an arm64 host installed an x86_64 CLI.
- **The install guard compares versions.** The source playbook used
  `creates: /usr/local/bin/aws`, which made its own `--update` flag unreachable: once the
  CLI existed, no later version could ever replace it.
- **Staging happens under `/var/tmp`**, not `/tmp`, which is a size-capped tmpfs on these
  hosts. The installer zip is ~70MiB and unpacks larger.

**No consumer in this repo pins an AWS CLI version**, so the pin is upstream's current
release rather than the unpinned-but-older version the source playbook happened to fetch.

Version override:

```bash
ansible-playbook cloud-cli/aws-cli.yml -e host=ws01 -e aws_cli_version=2.36.17
```

### On the signing key

AWS publishes its CLI signing key only in the
[installation documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html),
not at a fetchable URL, so it is embedded in the playbook and its fingerprint
(`FB5DB77FD5C118B80511ADA8A6310ACC4672475C`) checked after import. Do not replace it with
a keyserver copy: `keyserver.ubuntu.com` serves a stale self-signature for this key that
`gpg` reports as **expired on 2026-07-07**, while the documented copy carries an extended
expiry of 2027-07-01. Same key, same fingerprint, different expiry — and an expired copy
fails the verification step.

If AWS rotates the key, update both `aws_cli_public_key` and `aws_cli_key_fingerprint`.

### Per-user setup

The playbook configures no identity. Each account runs, for itself:

```bash
aws configure                 # static access keys, written to ~/.aws/credentials
aws configure sso             # IAM Identity Center
aws sts get-caller-identity   # confirm which identity is active
```

`~/.aws/` stays per-user. `AWS_PROFILE` and `AWS_REGION` are per-identity and are
deliberately not set system-wide; `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` are
secrets and must never be put in `/etc/environment`.

### Why not apt

Ubuntu 26.04 `universe` carries `awscli 2.31.35-1`, which is a genuine v2 rather than the
old v1 Python package, so decision-order point 1 arguably applies. It was rejected because
it trails upstream by several minor releases (2.36.x at the time of writing) and an LTS
package typically drifts further over its lifetime, while `aws` ships weekly. Revisit if
`apt-cache policy awscli` on the target ever lands close to upstream.

## azure-cli.yml

Installs the [Azure CLI](https://learn.microsoft.com/cli/azure/) from Microsoft's apt
repository.

| Path | Contents |
| --- | --- |
| `/opt/az/` | bundled Python interpreter and libraries |
| `/usr/bin/az` | wrapper script |
| `/etc/bash_completion.d/azure-cli` | shell completions, shipped by the package |
| `/etc/apt/sources.list.d/azure-cli.sources` | repository definition, signing key inline |

The package already installs to root-owned paths and its completions are already a
system-wide drop-in, so this playbook has no dependency on the `/etc/profile.d` bootstrap
that `tools/modern-cli-tools.yml` provides.

**What changed versus `cloud-cli/azure-cli.yml`.** The mechanism is unchanged — same
package, same repository, same paths — so this was correctness work:

- **The version is pinned** (`azure_cli_version`), with `allow_downgrade` so that moving
  the pin backwards actually applies instead of being silently satisfied by a newer
  install. The source playbook took `state: present`, i.e. whatever was newest that day.
- **The repository is declared with `ansible.builtin.deb822_repository`** and the signing
  key is embedded in its `Signed-By` field. The source playbook's `get_url` +
  `shell: gpg --dearmor` + `apt_repository` reported `changed` on every single run; this
  reports `changed` only when the definition actually moves.
- **The signing key is pinned in the playbook** rather than downloaded at run time, so a
  rotated key is a reviewed edit rather than something a run picks up silently.
- **The architecture comes from facts.** The source playbook hardcoded `arch=amd64`; the
  repository publishes `arm64` too.
- **The suite map is kept** (`resolute`/`plucky` → `noble`) and is still required:
  `packages.microsoft.com/repos/azure-cli/dists/` has `noble` but returns 404 for both
  `resolute` and `plucky`. The suite is also part of the package version
  (`2.89.0-1~noble`), so the pin is composed from the two rather than written out.
- **The prerequisite list shrank** to `ca-certificates` and `python3-debian` (which
  `deb822_repository` needs). `apt-transport-https`, `curl`, `gnupg` and `lsb-release` are
  gone: apt has spoken https natively since 1.5, the codename comes from facts, and
  nothing dearmors a key any more.
- **The smoke test runs `az` as uid 65534** with a scratch `HOME` under `/var/tmp`.

Version override:

```bash
ansible-playbook cloud-cli/azure-cli.yml -e host=ws01 -e azure_cli_version=2.89.0
```

### It supersedes the single-user apt source

Task 3 removes `/etc/apt/sources.list.d/azure-cli.list`, which
`cloud-cli/azure-cli.yml` and `cloud-cli/azure-devops-cli.yml` both wrote for this same
repository. Left in place beside the new `.sources` file, apt reads the repository twice
and warns that the target is configured multiple times. The old keyring
(`/etc/apt/keyrings/microsoft.gpg`) is deliberately left alone — no other playbook in this
repo references it, and an unused keyring is inert.

`gui-tools/vscode.yml` also adds a `packages.microsoft.com` repository, but a different one
(`/repos/code`) under its own filename and keyring, so the two do not collide.

### Per-user setup

The playbook configures no identity. Each account runs, for itself:

```bash
az login                     # interactive browser login; token cache in ~/.azure
az login --use-device-code   # for a session with no local browser
az account show              # confirm which subscription is active
```

`~/.azure/` stays per-user and no environment variable is set. Service principal secrets
(`AZURE_CLIENT_SECRET`) must never go in `/etc/environment`.

## azure-devops-cli.yml

Installs the Azure CLI exactly as `azure-cli.yml` does, then adds the
[azure-devops extension](https://learn.microsoft.com/azure/devops/cli/) to the CLI's
**system** extension directory.

| Path | Contents |
| --- | --- |
| `/usr/bin/az`, `/opt/az/` | the CLI, from apt — as `azure-cli.yml` |
| `/opt/az/lib/python3.<minor>/site-packages/azure-cli-extensions/azure-devops` | the extension, root-owned |

The azure-cli half duplicates `azure-cli.yml` on purpose — self-contained playbooks are
policy — using the same repository name, suite, key and pin, so **running both is safe and
installs one package**.

**What changed versus `cloud-cli/azure-devops-cli.yml`.** This is the one genuinely broken
install in `cloud-cli/`, so unlike the others this is reach work, not just correctness:

- **`az extension add --system`, as root.** The source playbook ran `az extension add`
  with `become: no`, which installs into the invoking account's
  `~/.azure/cliextensions` — so `az devops` worked for exactly the person who ran the
  playbook and was invisible to every other account, even though the `az` underneath it
  was a system-wide apt package.
- **The extension version is pinned** (`az_devops_ext_version`) and guarded on the version
  the CLI reports, not on the directory existing.
- **`az devops configure --defaults` is gone** (source tasks 8 and 9). It wrote one
  account's config, from the *installer's* environment via `lookup('env', ...)`. Defaults
  are now either per-user (each account runs the command itself) or genuinely shared (a
  play var, below).
- **The extension tree gets explicit world-readable modes**, since pip applies root's
  umask rather than a mode of its own.
- **The verification is the point of the playbook**: uid 65534, with an empty `HOME` and no
  extension of its own, must both discover the system extension *and* load the `az devops`
  command group. That is precisely the regression the source playbook has.

Version overrides:

```bash
ansible-playbook cloud-cli/azure-devops-cli.yml -e host=ws01 -e az_devops_ext_version=1.0.6
```

Pin to the version `az extension list-versions --name azure-devops` marks *max compatible
version* for the installed CLI, not to the newest published: a newer extension than the
CLI supports will install and then fail at load time.

### The extension path moves with the CLI's bundled Python

The system extension directory lives under the CLI's own Python environment
(`/opt/az/lib/python3.<minor>/site-packages/azure-cli-extensions`), so an azure-cli upgrade
that changes that minor version leaves the extension behind. This is not hypothetical:
`2.86.0-1~noble` bundles Python 3.13 and `2.89.0-1~noble` bundles 3.14.

The playbook handles it rather than documenting around it — it resolves the path at run
time from `az extension show --query path` and never hardcodes it, and because the guard
compares the *reported* version, an orphaned extension simply looks uninstalled and is
reinstalled on the next run. Since this playbook installs the CLI itself, one run does
both, in that order.

### Shared defaults versus per-user setup

Per-identity setup belongs to each account:

```bash
az login                                                    # token cache in ~/.azure
az devops configure --defaults organization=https://dev.azure.com/YOUR_ORG
az devops configure --defaults project=YOUR_PROJECT
export AZURE_DEVOPS_EXT_PAT=<pat>                           # SECRET — keep it in $HOME
```

`AZURE_DEVOPS_EXT_PAT` is a secret: it belongs in the user's own shell configuration at
mode `0600`, never in `/etc/environment`, which is shared and world-readable.

A default org or project that genuinely applies to *everyone* is a play var instead, off
unless asked for:

```bash
ansible-playbook cloud-cli/azure-devops-cli.yml -e host=ws01 \
  -e azure_devops_default_organization=https://dev.azure.com/YOUR_ORG \
  -e azure_devops_default_project=YOUR_PROJECT
```

which writes `AZURE_DEVOPS_EXT__DEFAULTS_ORGANIZATION` and
`AZURE_DEVOPS_EXT__DEFAULTS_PROJECT` to `/etc/environment` (PAM applies it at login, so
sessions started before the run need a re-login). An empty var *skips* rather than removes,
so a later run without the flag does not silently drop what an earlier one set; clearing a
value is a manual edit.

**The double underscore is not a typo.** The extension builds its knack config with the
prefix `AZURE_DEVOPS_EXT_`, and knack appends another `_` before `<SECTION>_<OPTION>`, so
the override for `defaults.organization` is `AZURE_DEVOPS_EXT__DEFAULTS_ORGANIZATION`.
Verified on the target: with that name, `az devops project list` gets past organization
resolution and fails on credentials; with `AZURE_DEVOPS_ORG` (the name the source playbook
used) or `AZURE_DEFAULTS_ORGANIZATION` (the azure-cli *core* spelling) it still fails with
`--organization must be specified`. Task 20a asserts this whenever a shared org is set —
a shared default under an unread name is invisible, since the variable is set,
`/etc/environment` looks right, and every user still gets an error.

Note how close `AZURE_DEVOPS_EXT__DEFAULTS_*` sits to the secret `AZURE_DEVOPS_EXT_PAT`.

## gcloud-cli.yml

Installs the [Google Cloud CLI](https://cloud.google.com/sdk/docs) from Google's apt
repository.

| Path | Contents |
| --- | --- |
| `/usr/lib/google-cloud-sdk/` | the SDK itself |
| `/usr/bin/gcloud`, `/usr/bin/gsutil`, `/usr/bin/bq` | wrappers |
| `/etc/apt/sources.list.d/google-cloud-sdk.sources` | repository definition, key inline |

**What changed versus `cloud-cli/gcloud-cli.yml`.** Same package, same repository; the
work was correctness plus removing two environment lookups:

- **A5 cleanup** — `deb822_repository` with Google's armored key embedded in `Signed-By`,
  replacing `get_url` + `shell: gpg --dearmor` + `apt_repository`.
- **Pinned** (`gcloud_cli_version`) with `allow_downgrade`. The package version carries a
  Debian revision (`579.0.0-0`) while the CLI reports `579.0.0`, so the two are composed
  from one pin rather than written out separately.
- **Architecture from facts.** The source playbook set none at all.
- **`GOOGLE_CLOUD_PROJECT` / `GOOGLE_CLOUD_LOCATION` are gone.** The source playbook read
  them from the *installer's* environment with `lookup('env', ...)` and printed them back
  as instructions, so the advice each user saw depended on whoever ran the playbook. A
  project and a region are per-identity (A3), so they are not set system-wide at all.

### Per-user setup

```bash
gcloud auth login                       # token store in ~/.config/gcloud
gcloud auth application-default login   # for client libraries
gcloud config set project YOUR_PROJECT
gcloud config set compute/region YOUR_REGION
```

Service account key files are secrets: keep them in `$HOME` at mode `0600`.

## github-cli.yml

Installs the [GitHub CLI](https://cli.github.com/) from GitHub's apt repository.

| Path | Contents |
| --- | --- |
| `/usr/bin/gh` | the CLI |
| `/etc/apt/sources.list.d/github-cli.sources` | repository definition |
| `/etc/apt/keyrings/github-cli.gpg` | repository signing keyring |

**What changed versus `cloud-cli/github-cli.yml`.** Same package, same repository:
A5 cleanup, a version pin with `allow_downgrade`, architecture from facts (the source
hardcoded `arch=amd64`), and the keyring no longer re-downloaded with `force: true` on
every run.

### The signing key is fetched, not pinned — deliberately

Unlike `azure-cli.yml`, `opentofu.yml` and `gcloud-cli.yml`, which embed an armored key
in `Signed-By`, this playbook passes `deb822_repository` the **key URL** and asserts a
pinned **fingerprint** afterwards. Two reasons, and the second is the important one:

1. GitHub publishes a *binary* keyring, which cannot be embedded in a deb822 field.
2. The keyring holds two keys, and the one currently signing the repository
   (`2C6106201985B60E6C7AC87323F3D4EA75716059`) **expires 2026-09-05**. A pinned copy of
   today's key would stop working; fetching each run means a host picks up GitHub's
   rotation to the successor as soon as it is published.

The assertion is therefore against the successor — the non-expiring
`7F38BBB59D064DBCB3D84D725612B36462313325`, which will still be in the keyring after the
rotation — rather than against the expiring key, which would turn a routine rotation into
a failed run. If GitHub ever replaces *both*, task 6 fails loudly and the fingerprint is
a one-line edit.

### Per-user setup

```bash
gh auth login      # writes ~/.config/gh/hosts.yml
gh auth status     # confirm which account is active
```

`GH_TOKEN` is a secret and must never go in `/etc/environment`.

## gitlab-cli.yml

Installs the [GitLab CLI](https://gitlab.com/gitlab-org/cli) from the upstream `.deb`.

| Path | Contents |
| --- | --- |
| `/usr/bin/glab` | the CLI |

**What changed versus `cloud-cli/gitlab-cli.yml`.** This one was doing more than cosmetic
damage:

- **The version is pinned.** The source playbook queried GitLab's release API for whatever
  was newest *at that moment*, so two hosts provisioned a week apart silently got
  different versions and no run record said which.
- **The download is verified** against the sha256 in the release's own `checksums.txt`,
  resolved at run time so a version override stays a one-flag change. The source playbook
  verified nothing.
- **Architecture from facts.** The source matched `glab_.*_linux_amd64\.deb` with a regex
  and would have installed an amd64 package on an arm64 host.
- **Staging moved to `/var/tmp`**, which is disk-backed; `/tmp` is a size-capped tmpfs.

Why not apt: Ubuntu `resolute/universe` carries `glab 1.53.0-1build1`, far behind
upstream, and there is no vendor apt repository.

A dry run is genuinely useful here: `--check` fetches `checksums.txt` and validates that
the pinned version exists upstream with an asset for this architecture, without
downloading or installing anything.

### Per-user setup

```bash
glab auth login    # writes ~/.config/glab-cli/config.yml
glab auth status
```

`GITLAB_TOKEN` is a secret and must never go in `/etc/environment`.

## opentofu.yml

Installs [OpenTofu](https://opentofu.org/) from the packagecloud-hosted vendor repository.

| Path | Contents |
| --- | --- |
| `/usr/bin/tofu` | the CLI |
| `/etc/apt/sources.list.d/opentofu.sources` | repository definition, key inline |

**What changed versus `cloud-cli/opentofu.yml`.** A5 cleanup (which here removes *two*
`shell: gpg --dearmor` tasks and two downloads), a version pin with `allow_downgrade`, and
architecture from facts.

### One signing key, not two

The source playbook put two keys in `signed-by`:
`https://get.opentofu.org/opentofu.gpg` and the packagecloud repository key. Only the
second is dropped-in-anger material — the repository's `InRelease` is signed by subkey
`59D41234F9F7AFD007143F6A70DF59811A8B9109` of the packagecloud key
(`F4AF70F66EAC4337EEECC97407D3DFCD4C61499F`), verified directly against the published
`InRelease`. The other key's own user ID says it signs OpenTofu **providers**, not the apt
repository. A key that signs nothing apt reads does not belong in `Signed-By`, so it is
dropped.

### The smoke test formats a deliberately broken file

`tofu fmt -check` on already-tidy input is indistinguishable from a `tofu` that parsed
nothing, so the playbook writes a misformatted `main.tf` and asserts that tofu **names**
it. The task needs `chdir` — see the note in the playbook: an unprivileged process
inherits a working directory it cannot read, and tofu re-expresses any path it is given
relative to that directory before failing on it.

## prometheus-cli.yml

Installs `promtool` and `amtool` from the Ubuntu archive.

| Path | Contents |
| --- | --- |
| `/usr/bin/promtool` | from the `promtool` package |
| `/usr/bin/amtool` | from the `prometheus-alertmanager` package |

This installs **clients only**. `prometheus-alertmanager` is here purely because it is
what ships `amtool`; its daemon is stopped and disabled, as the source playbook also did.
Deploying an actual Alertmanager is out of scope.

**What changed versus `cloud-cli/prometheus-cli.yml`.** Both packages are pinned with
`allow_downgrade`, the versions are verified after install, and both tools now validate a
real config file as uid 65534. The source playbook installed two packages unpinned and
checked nothing.

Unlike the vendor-repo playbooks, these pins are **release-specific**: apt candidates
differ between 24.04 and 26.04, and an install fails outright when the pin is not what the
target's sources carry. Check `apt-cache policy` on the target before bumping — the
`shellcheck.yml` finding in MIGRATION.md.

Version overrides:

```bash
ansible-playbook cloud-cli/prometheus-cli.yml -e host=ws01 \
  -e promtool_version=2.53.5+ds1-3 -e alertmanager_version=0.28.1+ds-3
```
