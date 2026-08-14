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

## Environment variables

**No playbook here sets a single environment variable, and none reads one.** Endpoint
configuration comes from `vars:` overridable with `-e`; identity comes from each account's
own `$HOME`. This section is the documentation that replaces `cloud-cli/env-tmpl.sh`, the
shared template the old playbooks read from — deleted rather than migrated, because a
tracked file that looks like the place to write tokens is a file someone eventually commits
with tokens in it.

### Where each kind belongs

| Kind | Example | Goes in |
| --- | --- | --- |
| Shared, non-secret endpoint | `VAULT_ADDR`, `INFLUX_HOST` | `/etc/environment`, *only* if every account really should point at the same server. Nothing here writes it for you. |
| Per-identity, non-secret | `AWS_PROFILE`, `CLOUDSDK_CORE_PROJECT` | your own shell, or the tool's own config (`gcloud config set project`) |
| **Secret** | every `*_TOKEN`, `*_PAT`, `*_SECRET_ACCESS_KEY` | your own `$HOME` at mode `0600` — **never** `/etc/environment`, which is world-readable |

For the secrets, keep a file only you can read and source it from your own `~/.bashrc`:

```bash
umask 077
mkdir -p ~/.config/cloud-cli
cat > ~/.config/cloud-cli/env.sh <<'SH'
export GH_TOKEN=...
export JIRA_API_TOKEN=...
SH
chmod 600 ~/.config/cloud-cli/env.sh

# in ~/.bashrc:
[ -r ~/.config/cloud-cli/env.sh ] && . ~/.config/cloud-cli/env.sh
```

Most tools here need no environment variable at all — `aws configure`, `az login`,
`gcloud auth login`, `gh auth login`, `glab auth login`, `jira init` and
`influx config create` all write per-user config, which is the supported path. Reach for an
environment variable when you want the non-interactive one (CI, a script), not as the
default way to configure a workstation account.

### Which names the tools actually read

Checked against the binaries on the target, because **a name that appeared in the old
template is not evidence the tool reads it** — three of them turned out to be the old
playbooks' own inputs, used only to interpolate an instruction into a message.

| Variable | Tool | Kind | Status |
| --- | --- | --- | --- |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `aws` | secret | read — `aws configure list` names the missing half |
| `AWS_PROFILE`, `AWS_DEFAULT_REGION` | `aws` | per-identity | read |
| `AZURE_DEVOPS_EXT__DEFAULTS_ORGANIZATION`, `AZURE_DEVOPS_EXT__DEFAULTS_PROJECT` | `az devops` | shared | read (double underscore — knack's prefix plus the section separator) |
| `AZURE_DEVOPS_EXT_PAT` | `az devops` | secret | read |
| `CLOUDSDK_CORE_PROJECT` | `gcloud` | per-identity | read |
| `GH_TOKEN` / `GITHUB_TOKEN` | `gh` | secret | read, in that precedence |
| `GITLAB_TOKEN` | `glab` | secret | read — `glab auth status` says so explicitly |
| `GRAFANA_SERVER` | `gcx` | shared | read |
| `GRAFANA_TOKEN` | `gcx` | secret | read |
| `INFLUX_HOST`, `INFLUX_ORG` | `influx` | shared | read |
| `INFLUX_TOKEN` | `influx` | secret | read |
| `JIRA_API_TOKEN` | `jira` | secret | read |
| `VAULT_ADDR` | `vault` | shared | read |
| `VAULT_TOKEN` | `vault` | secret | read |
| ~~`JIRA_URL`, `JIRA_LOGIN`~~ | `jira` | — | **not read.** Both live in `~/.config/.jira/.config.yml`, written by `jira init`. |
| ~~`AZURE_DEVOPS_ORG`, `AZURE_DEVOPS_PROJECT`~~ | `az devops` | — | **not read.** Nor is `AZURE_DEFAULTS_ORGANIZATION`. Use the `EXT__DEFAULTS` names above. |
| ~~`GOOGLE_CLOUD_PROJECT`, `GOOGLE_CLOUD_LOCATION`~~ | `gcloud` | — | **not read by the CLI.** With `GOOGLE_CLOUD_PROJECT` set, `gcloud config get project` still prints `(unset)`; `CLOUDSDK_CORE_PROJECT` works. Google's *client libraries* read `GOOGLE_CLOUD_PROJECT`, which is where the confusion comes from. |

`jenkins-cli` is the one exception to "no playbook here sets an environment variable":
`JENKINS_URL` is shared, non-secret endpoint configuration, and
[`jenkins-cli.yml`](#jenkins-cliyml) writes it to `/etc/profile.d/jenkins-cli.sh` from a play
var. Its two credential variables, `JENKINS_USER_ID` and `JENKINS_API_TOKEN`, are per-account
and are not written anywhere — both are read by the wrapper from your own environment.

---

Each section below has a **"What changed versus `cloud-cli/<tool>.yml`"** paragraph. Those
source playbooks no longer exist: all thirteen were retired on 2026-08-10 once their
successors here were verified, and `cloud-cli/` is gone with them — this directory is the
only generation left. Read the comparison as history; `git log --diff-filter=D -- cloud-cli/`
brings any of them back.

The `ansible-playbook cloud-cli/<tool>.yml` commands in this file are relative to
`_multi-user/`, which is where they must be run from, so they refer to the playbooks here and
not to the retired ones.

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

`gui-tools/vscode.yml` also added a `packages.microsoft.com` repository, but a different one
(`/repos/code`) under its own filename and keyring, so the two never collided. That playbook was
[retired](../../README.md#retired-gui-tools) on 2026-08-14; a host that ran it keeps the
`vscode.list` source and the `/usr/share/keyrings/packages.microsoft.gpg` keyring, which are
still none of this playbook's business.

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

## gcx-cli.yml

Installs [gcx](https://github.com/grafana/gcx), the Grafana CLI, from its GitHub release
tarball.

| Path | Contents |
| --- | --- |
| `/usr/local/bin/gcx` | the binary, root-owned, mode 0755 |
| `/etc/bash_completion.d/gcx` | completions, generated at install time |

**What changed versus `cloud-cli/gcx-cli.yml`.** This is reach work, not correctness work:
the source playbook ran `brew tap grafana/grafana` and `brew install` as
`lookup('env', 'USER')`, so the binary lived under `/home/linuxbrew` owned by whoever ran
the play — one account's install that everyone else inherited by accident of `PATH`, and
that account could rewrite.

- **No Homebrew.** The upstream release tarball, pinned (`gcx_cli_version`) and verified
  against the sha256 in `gcx_<version>_checksums.txt`, installed to a root-owned path.
- **Architecture from facts**, with an explicit map so an unmapped architecture fails
  loudly instead of silently taking amd64.
- **The `GRAFANA_SERVER` lookup is gone** (A2/A3). Unlike jira-cli's `JIRA_URL`, this
  *is* a name gcx reads — verified on the target — but it names a site's Grafana instance,
  which this repo does not have, so it is set nowhere. If you ever want a site default,
  put it in `/etc/environment` from a play var. Never `GRAFANA_TOKEN`, which is a secret.
- **Completions go to `/etc/bash_completion.d`**, generated by `gcx completion bash`.

Version override:

```bash
ansible-playbook cloud-cli/gcx-cli.yml -e host=ws01 -e gcx_cli_version=1.0.0
```

### The smoke test needs a working directory, not just a HOME

`gcx` merges a repository-level `.gcx.yaml` from the **current directory** into its config
layering. With the cwd left wherever ansible ran from, `gcx config current-context` as uid
65534 dies on `lstat .../.gcx.yaml: permission denied` — a correct install failing its own
verification on the working directory. Every smoke test in this playbook therefore runs
with `chdir` set to the scratch `HOME`, which is also why that directory is created with
`check_mode: false` (`command` validates `chdir` before check mode skips the task).

The check itself is `gcx config current-context`, not `gcx config check`: without a stack
configured the latter exits non-zero by design, which is authentication state rather than
reachability.

### Per-user setup

```bash
gcx login                    # writes ~/.config/gcx/config.yaml
gcx config check             # confirm the context resolves
```

`~/.config/gcx/` and `~/.local/state/gcx/` stay per-user. `GRAFANA_TOKEN` is a secret and
must never go in `/etc/environment`.

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

## influx-cli.yml

Installs the [InfluxDB v2 CLI](https://docs.influxdata.com/influxdb/v2/reference/cli/influx/)
from InfluxData's release archive.

| Path | Contents |
| --- | --- |
| `/usr/local/lib/influx-cli/<version>/influx` | the binary, root-owned |
| `/usr/local/bin/influx` | symlink to the active version |
| `/etc/bash_completion.d/influx` | completions, generated at install time |

**What changed versus `cloud-cli/influx-cli.yml`.** Reach work: the source playbook ran
`brew install influxdb-cli` as `lookup('env', 'USER')`. Two details make this one unlike
the other de-brew playbooks.

### The release does not live on GitHub

`influxdata/influx-cli`'s GitHub releases carry **no assets at all**. The binaries are
published at `https://dl.influxdata.com/influxdb/releases/` with a `.sha256` sibling per
asset — one file per asset, not a shared `checksums.txt` — and the entry inside it is
`<hash>  /root/project/packages/<file>`, InfluxData's build path baked in. The match
pattern allows that prefix; anchoring on the bare filename finds nothing.

The v2.8.0 release notes announce a rename from `influxdb2-client-*` to `influxdb2-cli-*`,
but the published asset is still `influxdb2-client-*`; `influxdb2-cli-2.8.0-linux-amd64.tar.gz`
is a 404. Try both spellings when bumping the pin.

### `influx version` does not report the version

Upstream ships these binaries without the version stamp: `influx version` prints
`Influx CLI dev (git: <sha>)` for every release. There is nothing in the tool's output to
compare a pin against, so the install is versioned in the filesystem instead — a
per-version directory with a symlink into it, the shape AWS's own installer uses — and the
guard reads the symlink target. `ls -l /usr/local/bin/influx` is therefore the way to see
which version is active. A stray non-symlink binary at that path (a leftover from another
install method) is replaced rather than trusted.

Earlier versions are left in `/usr/local/lib/influx-cli/` and can be removed by hand.

Version override:

```bash
ansible-playbook cloud-cli/influx-cli.yml -e host=ws01 -e influx_cli_version=2.8.0
```

### Per-user setup

```bash
influx config create --config-name default --host-url <url> \
    --org <org> --token <token> --active     # writes ~/.influxdbv2/configs
influx config list                           # confirm which config is active
```

`INFLUX_HOST` and `INFLUX_ORG` are shared, non-secret configuration and the CLI does read
them (verified), but no playbook sets them: there is no site-wide InfluxDB here.
`INFLUX_TOKEN` is a secret and must never go in `/etc/environment`.

## jenkins-cli.yml

Installs the [Jenkins CLI](https://www.jenkins.io/doc/book/managing/cli/) from the Jenkins
project's own Maven repository.

| Path | Contents |
| --- | --- |
| `/usr/local/lib/jenkins-cli.jar` | the CLI, root-owned, mode 0644 |
| `/usr/local/bin/jenkins-cli` | wrapper script |
| `/usr/local/bin/jenkins` | alias symlink to the wrapper |
| `/etc/profile.d/jenkins-cli.sh` | the shared, non-secret default `JENKINS_URL` |

No architecture map, unlike everything else here: a jar is a jar. The JRE
(`default-jre-headless`) is the only native dependency and comes from apt.

**What changed versus `cloud-cli/jenkins-cli.yml`.** MIGRATION2.md filed this playbook under
one defect — the invoking shell's `$JENKINS_URL` baked into a file every account executes —
but the bigger one is where the jar came from:

- **The jar is no longer downloaded from a running Jenkins.** The source playbook fetched
  `{{ jenkins_url }}/jnlpJars/jenkins-cli.jar`, so a host with no reachable Jenkins **could
  not install the CLI at all** — fatal when provisioning a fresh workstation — and the
  version installed was whatever server happened to be up, unpinned and unverified. This
  workstation had `2.541.3` by that route.
- **Pinned and checksum-verified** (`jenkins_cli_version`) from
  `repo.jenkins-ci.org/releases/org/jenkins-ci/main/cli/<version>/`, where each release
  publishes the jar with a `.sha256` sibling.
- **`jenkins_url` is a play var** (A2), rendered into both the wrapper's fallback and the
  `/etc/profile.d` default in the same run, so the two cannot drift.
- **The smoke test is real**, where the source playbook ran `jenkins-cli help` with
  `failed_when: false` — which asserts nothing at all.

Overrides:

```bash
ansible-playbook cloud-cli/jenkins-cli.yml -e host=ws01 \
  -e jenkins_url=http://ci.example.com:8080 -e jenkins_cli_version=2.576
```

Changing `jenkins_url` re-renders the wrapper and the profile drop-in without touching the
jar, so pointing a fleet at a new Jenkins is a cheap re-run.

### Pinning a jar the server also serves

Jenkins' documentation tells you to fetch the CLI from your own server so that CLI and server
versions match, and pinning a Maven artifact deliberately decouples them. The CLI is tolerant
in practice, but **set `jenkins_cli_version` near your server's Jenkins version** rather than
leaving it at whatever this file last said.

The published artifact is the same shaded, standalone-runnable jar the server hands out —
verified before adopting it: 11.7MB, `Main-Class: hudson.cli.CLI`, `Implementation-Version`
matching the release, and its sha256 matching the published one.

Two mechanics worth knowing if you touch this playbook:

- `repo.jenkins-ci.org` answers with a 302 to a presigned object-store URL. `get_url` follows
  redirects, but a bare `curl` without `-L` **silently writes a zero-byte file** here.
- The version guard reads `Implementation-Version` out of the jar's own
  `META-INF/MANIFEST.MF` rather than encoding the version in a path. Where an artifact
  describes itself, ask it; `influx-cli.yml` needs its versioned directory only because
  upstream ships those binaries unstamped.

### The smoke test aims at a closed port

Every `jenkins-cli` subcommand is executed by the server, and the command list itself is
fetched from it, so there is no offline code path to exercise — A4's tiers 1 and 2 do not
exist for this tool. What the check asserts instead is that an arbitrary uid gets all the way
to the network boundary: JVM starts, jar loads, the shaded websocket client initialises,
arguments parse, a connection is attempted, and it fails **only** because nothing is
listening on `127.0.0.1:1`. A missing JRE, an unreadable jar or a truncated download all fail
earlier and differently, which is exactly what this distinguishes.

**Do not build a smoke test on `-help`: it hangs.** It does not print usage and exit, so any
check using it blocks the play indefinitely. Every invocation in this playbook is wrapped in
`timeout` and given `stdin: ""` for the same reason.

### Per-user setup

The playbook configures no identity. Each account exports, for itself:

```bash
export JENKINS_USER_ID=<user>
export JENKINS_API_TOKEN=<api-token>   # Jenkins > Configure > API Token
jenkins who-am-i                       # confirm which account is active
```

Keep them in `~/.config/cloud-cli/env.sh` at mode `0600` as described under
[Environment variables](#environment-variables). `JENKINS_API_TOKEN` is a secret and must
never go in `/etc/environment` or `/etc/profile.d`, both of which are world-readable.
`JENKINS_URL` is not a secret and *is* set there — exporting your own overrides it.

## jira-cli.yml

Installs [jira-cli](https://github.com/ankitpokhrel/jira-cli) from its GitHub release
tarball.

| Path | Contents |
| --- | --- |
| `/usr/local/bin/jira` | the binary, root-owned, mode 0755 |
| `/etc/bash_completion.d/jira` | completions, generated at install time |

**What changed versus `cloud-cli/jira-cli.yml`.** Reach work: the source playbook ran
`brew tap ankitpokhrel/jira-cli` and `brew install` as `lookup('env', 'USER')`.

- **No Homebrew, no tap.** The upstream release tarball, pinned (`jira_cli_version`) and
  verified against the sha256 in the release's `checksums.txt`.
- **Architecture from facts** — and note the asset arch strings here are `x86_64` /
  `arm64`, not the `amd64` / `arm64` the other playbooks map to. A map copied from
  `gcx-cli.yml` would 404 on every host.
- **`JIRA_URL` and `JIRA_LOGIN` are gone** (A2/A3) — and unlike `GRAFANA_SERVER`, they were
  never variables the tool read. See below.
- **Completions go to `/etc/bash_completion.d`**, generated by `jira completion bash`.

Version override:

```bash
ansible-playbook cloud-cli/jira-cli.yml -e host=ws01 -e jira_cli_version=1.7.0
```

### jira-cli does not read `JIRA_URL` or `JIRA_LOGIN`

The source playbook read both with `lookup('env', ...)` and interpolated them into its
closing message, which made them look like configuration the tool honours. They are not:
with both set, `jira issue list` still exits 1 with *"The tool needs a Jira API token to
function"*, and the binary's only `JIRA_*` variables are `JIRA_API_TOKEN`,
`JIRA_AUTH_TYPE`, `JIRA_BROWSER`, `JIRA_CONFIG_FILE` and `JIRA_EDITOR`. Server and login
come from `~/.config/.jira/.config.yml`, written by `jira init`.

This is the second instance of the same trap as `AZURE_DEVOPS_ORG` — see MIGRATION2.md.

### Per-user setup

```bash
jira init                    # writes ~/.config/.jira/.config.yml
jira me                      # confirm which account is active
```

`JIRA_API_TOKEN` is a secret and must never go in `/etc/environment`.

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

## promtool.yml

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
ansible-playbook cloud-cli/promtool.yml -e host=ws01 \
  -e promtool_version=2.53.5+ds1-3 -e alertmanager_version=0.28.1+ds-3
```

## vault-cli.yml

Installs the [Vault CLI](https://developer.hashicorp.com/vault/docs/commands) from
HashiCorp's apt repository.

| Path | Contents |
| --- | --- |
| `/usr/bin/vault` | the CLI |
| `/etc/bash_completion.d/vault` | completion registration |
| `/etc/apt/sources.list.d/hashicorp.sources` | repository definition |
| `/etc/apt/keyrings/hashicorp.asc` | repository signing key |

**What changed versus `cloud-cli/vault-cli.yml`.** Reach work plus an A5 cleanup: the
source playbook ran `brew tap hashicorp/tap` and `brew install` as
`lookup('env', 'USER')`. HashiCorp publishes an apt repository, so the migrated playbook
is an ordinary vendor-repo one — pinned (`vault_cli_version`) with `allow_downgrade`,
architecture from facts, `deb822_repository`, and no `VAULT_ADDR` written into anyone's
`~/.bashrc`.

Version override:

```bash
ansible-playbook cloud-cli/vault-cli.yml -e host=ws01 -e vault_cli_version=2.0.4-1
```

### Read this before running it on a host that also serves Vault

`vault` is **one package** for client and server. There is no CLI-only package, so on a
host that also runs a Vault server:

- Bumping `vault_cli_version` upgrades the server's binary too. The running process keeps
  executing the old code — during this migration, `dpkg-query` reported `2.0.4-1` while the
  running server still reported `2.0.0` on its status endpoint. The new binary takes effect
  at the next `vault.service` restart, which for file storage means unsealing again.
- `/etc/vault.d/vault.hcl` is a dpkg conffile. An upgrade keeps a locally modified copy
  (ansible's `apt` module passes `force-confold`), so a server's configuration survives.
- **The unit is left alone.** Unlike `promtool.yml`, which must disable the
  Alertmanager daemon its package enables, HashiCorp's `postinst` does not enable or start
  `vault.service` — it only runs `daemon-reload`. Anything other than `disabled` was put
  there by something else on the host, and turning off a server this playbook did not start
  is not a CLI installer's business. Task 19 reports the state instead of changing it.

This repo ships no Vault server playbook: `services/vault.yml` was deleted rather than
migrated, along with the local server it had deployed. The rest of `services/` followed it —
see [Retired: `services/`](../../README.md#retired-services).

A "client-only" install still lays down server scaffolding, because the package does:
a `vault` system user, a self-signed cert under `/opt/vault/tls`, `/opt/vault/data`, a
`vault.service` unit, and `setcap cap_ipc_lock=+ep` on the binary. All of it is inert until
something enables the unit.

### It supersedes the deleted `services/vault.yml`'s apt source

Task 3 removes `/etc/apt/sources.list.d/apt_releases_hashicorp_com.list`, which
`services/vault.yml` wrote for this same repository. Left beside the new `.sources` file,
apt reads the repository twice and warns that the target is configured multiple times. The
old keyring (`/etc/apt/keyrings/hashicorp-archive-keyring.asc`) is left alone — it holds
the same key, byte for byte, and an unused keyring is inert.

The task stays although the playbook that wrote the file is gone: every host it ran on
still has the file, and nothing else will remove it. Same shape as `github-cli.yml` and
`azure-cli.yml` clearing their own predecessors' `.list` files.

The suite is mapped to `noble` for the same reason. HashiCorp's Artifactory does publish
`resolute` (contrary to what MIGRATION2.md originally recorded), with identical content,
but the deleted playbook configured the repository with `noble`, and two entries for one
URI under different suites are two repositories to apt — so `noble` keeps the two agreeing
on hosts task 3 has not yet reached.

### The signing key is fetched, not pinned

HashiCorp's packaging key `798AEC654E5C15428C8E42EEAA16FCBCA621E701` **expires
2028-01-09**, so per A5 it is fetched each run — `deb822_repository` compares by checksum,
so that stays idempotent — and only its fingerprint is asserted. Pinning today's bytes
would turn the eventual rotation into a signature failure on every host. Same form as
`github-cli.yml`, opposite form to `azure-cli.yml`, whose key does not expire.

### The smoke test formats a policy file

`vault policy fmt` parses and rewrites HCL without contacting a server, so it is A4's
strongest tier — real offline work — where every other `vault` subcommand needs an address
and a token. `VAULT_ADDR` is deliberately left unset. The check also proves the package's
`setcap cap_ipc_lock=+ep` does not stop an arbitrary uid from executing the binary.

### Per-user setup

```bash
export VAULT_ADDR=https://<your-vault>:8200
vault login                  # writes ~/.vault-token
vault token lookup           # confirm which identity is active
```

`VAULT_ADDR` is shared, non-secret configuration and the CLI does read it, but no playbook
sets it: the deleted `services/vault.yml`'s habit of appending it to one account's
`~/.bashrc` is exactly the single-user breakage this migration removes. `VAULT_TOKEN` is a secret and must
never go in `/etc/environment`.

## Replacing the Homebrew installs

`jira`, `gcx`, `influx` and `vault` were previously installed with `brew` as
`lookup('env', 'USER')`. After running the migrated playbooks, the system-wide copies exist
but the Homebrew ones may still shadow them:

```bash
brew uninstall jira-cli
brew uninstall grafana/grafana/gcx
brew uninstall influxdb-cli
brew uninstall hashicorp/tap/vault
```

Each playbook asserts that a login shell resolves the tool to the system-wide path, running
`command -v` as uid 65534 under `env -i ... bash -lc` so that `PATH` comes purely from
`/etc/profile` and `/etc/bash.bashrc`. That catches a **system-wide** `brew shellenv`.
It cannot catch a `brew shellenv` line in an individual account's own `~/.bashrc`, which
shadows the system-wide binary for that account's interactive shells only — check those by
hand:

```bash
grep -l linuxbrew /home/*/.bashrc
```

On `localhost` this was done on 2026-08-11 and went further than the four formulae above: every
formula and tap was removed, then `/home/linuxbrew` and `~/.cache/Homebrew` deleted outright and
the `brew shellenv` block dropped from `~/.bashrc`. The steps here still apply to any other host
provisioned before `core/homebrew.yml` was retired. If you go as far as deleting the prefix,
list its `bin` and `lib` first — that run found a hand-built binary and an orphaned
`node_modules` under `/home/linuxbrew/.linuxbrew` that belonged to no formula.
