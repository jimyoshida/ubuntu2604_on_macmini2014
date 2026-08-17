# Cloud CLI Playbooks (multi-user workstations)

Standalone playbooks that install cloud and service CLI tools on a **shared** Ubuntu
workstation. They are the multi-user successors to `cloud-cli/`. See
[MIGRATION2.md](../../MIGRATION2.md) for the policy and the per-tool plan.

Run from `playbooks/`:

```bash
ansible-playbook cloud-cli/<tool>.yml -e host=<inventory host or group>
```

## Conventions

These playbooks follow the same rules as [`misc/`](../misc/README.md) — root-owned
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
own `$HOME`. There is deliberately no shared env template file to fill in: a tracked file
that looks like the place to write tokens is a file someone eventually commits with tokens
in it.

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

Checked against the actual binaries on the target — **a name that looks like
configuration is not evidence a tool reads it**; some names below turned out to only ever
be used to interpolate an instruction into a closing message.

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

The `ansible-playbook cloud-cli/<tool>.yml` commands in this file are relative to
`playbooks/`, which is where they must be run from.

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

**No consumer in this repo pins an AWS CLI version**, so the pin tracks upstream's current
release.

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
that `core/modern-tools.yml` provides.

Version override:

```bash
ansible-playbook cloud-cli/azure-cli.yml -e host=ws01 -e azure_cli_version=2.89.0
```

### Cleans up a stale apt source

This playbook removes `/etc/apt/sources.list.d/azure-cli.list` if present — left in place
beside the new `.sources` file, apt reads the repository twice and warns that the target is
configured multiple times. An old keyring at `/etc/apt/keyrings/microsoft.gpg` is
deliberately left alone: nothing in this repo references it, and an unused keyring is
inert.

A host may also carry a separate `packages.microsoft.com` repository under `vscode.list` (a
different path, `/repos/code`, with its own keyring at
`/usr/share/keyrings/packages.microsoft.gpg`) — the two never collide and are not this
playbook's business.

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
resolution and fails on credentials; with the plausible-looking `AZURE_DEVOPS_ORG` or
`AZURE_DEFAULTS_ORGANIZATION` (the azure-cli *core* spelling) it still fails with
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

The upstream release tarball is pinned (`gcx_cli_version`) and verified against the sha256
in `gcx_<version>_checksums.txt`, installed to a root-owned path. Architecture comes from
facts, with an explicit map so an unmapped architecture fails loudly instead of silently
taking amd64.

`GRAFANA_SERVER` is a name `gcx` genuinely reads (verified on the target) — it names a
site's Grafana instance, which this repo does not have, so it is set nowhere. If you ever
want a site default, put it in `/etc/environment` from a play var. Never `GRAFANA_TOKEN`,
which is a secret.

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

The version is pinned and the download verified against the sha256 in the release's own
`checksums.txt`, resolved at run time so a version override stays a one-flag change.
Architecture comes from facts. Staging happens under `/var/tmp`, which is disk-backed;
`/tmp` is a size-capped tmpfs on these hosts.

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

The jar is pinned and checksum-verified (`jenkins_cli_version`) from
`repo.jenkins-ci.org/releases/org/jenkins-ci/main/cli/<version>/`, where each release
publishes the jar with a `.sha256` sibling. `jenkins_url` is a play var, rendered into both
the wrapper's fallback and the `/etc/profile.d` default in the same run, so the two cannot
drift.

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
fetched from it, so there is no offline code path to exercise. What the check asserts instead
is that an arbitrary uid gets all the way to the network boundary: JVM starts, jar loads, the
shaded websocket client initialises, arguments parse, a connection is attempted, and it fails
**only** because nothing is listening on `127.0.0.1:1`. A missing JRE, an unreadable jar or a
truncated download all fail earlier and differently, which is exactly what this distinguishes.

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

The upstream release tarball is pinned (`jira_cli_version`) and verified against the
sha256 in the release's `checksums.txt`. Note the asset arch strings here are `x86_64` /
`arm64`, not the `amd64` / `arm64` that other playbooks in this directory map to — a map
copied from `gcx-cli.yml` would 404 on every host.

Version override:

```bash
ansible-playbook cloud-cli/jira-cli.yml -e host=ws01 -e jira_cli_version=1.7.0
```

### jira-cli does not read `JIRA_URL` or `JIRA_LOGIN`

`JIRA_URL` and `JIRA_LOGIN` look like configuration but are not read by the tool: with both
set, `jira issue list` still exits 1 with *"The tool needs a Jira API token to function"*,
and the binary's only `JIRA_*` variables are `JIRA_API_TOKEN`, `JIRA_AUTH_TYPE`,
`JIRA_BROWSER`, `JIRA_CONFIG_FILE` and `JIRA_EDITOR`. Server and login come from
`~/.config/.jira/.config.yml`, written by `jira init`.

### Per-user setup

```bash
jira init                    # writes ~/.config/.jira/.config.yml
jira me                      # confirm which account is active
```

`JIRA_API_TOKEN` is a secret and must never go in `/etc/environment`.

## loki-cli.yml

Installs [logcli](https://grafana.com/docs/loki/latest/query/logcli/), the Grafana Loki CLI,
as a single static binary from the `grafana/loki` GitHub release.

| Path | Contents |
| --- | --- |
| `/usr/local/bin/logcli` | the binary, root-owned, mode 0755 |

There is no per-user state and nothing added to a shell profile — logcli has no config file
at all. Endpoint and credentials come from flags or environment variables (`--addr` /
`LOKI_ADDR`, `LOKI_USERNAME`, `LOKI_PASSWORD`, `LOKI_BEARER_TOKEN`, `LOKI_ORG_ID`), and per
rules 1 and 2 above this playbook sets none of them: there is no site-wide Loki for this repo
to name, and the credentials are per-account secrets that must not land in world-readable
`/etc/environment`.

### How the install is put together

- **The pin** is **3.7.6**, upstream's current release as of 2026-08-17, read from the releases
  API rather than assumed.
- **Integrity.** `unarchive` straight from a URL would verify nothing, so the zip is fetched
  with `get_url` and checked against the `SHA256SUMS` the release publishes for every asset —
  an unverified 128 MB binary is never installed.
- **Architecture** comes from `ansible_facts['architecture']`, and an unmapped one fails
  loudly rather than installing an amd64 binary on arm64.
- **Cleanup and ownership.** The download is staged under `/var/tmp` (disk, not the
  size-capped `/tmp` tmpfs on these hosts) and removed once the binary is installed root-owned
  at mode 0755, so nothing is left behind and the owner is not left to a umask.

### `logcli --version` prints to stderr

kingpin, the flag library logcli uses, writes `--version` output to **stderr** and exits 0.
Both the idempotency check and the verification therefore read `.stderr`; reading `.stdout`
matches nothing, which is exactly how the first run of this playbook failed. The comparison is
against the full `logcli, version <x> ` prefix rather than a bare version substring, so a pin
of `3.7.6` cannot be satisfied by a hypothetical `3.7.60`.

### The smoke test runs a real query, offline

`logcli query --stdin '<LogQL>'` runs the real LogQL engine over stdin with no server
involved. The unprivileged check pipes two lines through a line filter and asserts that the
matching one comes back **and the non-matching one does not** — a binary that merely echoed
its input would otherwise pass. Query results go to stdout while logcli's `Common labels:`
banner goes to stderr, so only stdout is asserted on.

Version overrides:

```bash
ansible-playbook cloud-cli/loki-cli.yml -e host=ws01 -e loki_cli_version=3.7.6
```

## opentofu.yml

Installs [OpenTofu](https://opentofu.org/) from the packagecloud-hosted vendor repository.

| Path | Contents |
| --- | --- |
| `/usr/bin/tofu` | the CLI |
| `/etc/apt/sources.list.d/opentofu.sources` | repository definition, key inline |

### One signing key, not two

Only one key belongs in `Signed-By` here: the repository's `InRelease` is signed by subkey
`59D41234F9F7AFD007143F6A70DF59811A8B9109` of the packagecloud key
(`F4AF70F66EAC4337EEECC97407D3DFCD4C61499F`), verified directly against the published
`InRelease`. `https://get.opentofu.org/opentofu.gpg` is a tempting addition, but that key's
own user ID says it signs OpenTofu **providers**, not the apt repository — a key that signs
nothing apt reads does not belong in `Signed-By`.

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
what ships `amtool`; its daemon is stopped and disabled. Deploying an actual Alertmanager
is out of scope.

Both packages are pinned with `allow_downgrade`, the versions are verified after install,
and both tools validate a real config file as uid 65534.

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

Installed the standard vendor-repo way: pinned (`vault_cli_version`) with
`allow_downgrade`, architecture from facts, `deb822_repository`, and no `VAULT_ADDR`
written into anyone's `~/.bashrc`.

Version override:

```bash
ansible-playbook cloud-cli/vault-cli.yml -e host=ws01 -e vault_cli_version=2.0.4-1
```

### Read this before running it on a host that also serves Vault

`vault` is **one package** for client and server. There is no CLI-only package, so on a
host that also runs a Vault server:

- Bumping `vault_cli_version` upgrades the server's binary too. The running process keeps
  executing the old code until `vault.service` restarts — `dpkg-query` and the server's own
  status endpoint can report different versions in the meantime — and for file storage,
  restarting means unsealing again.
- `/etc/vault.d/vault.hcl` is a dpkg conffile. An upgrade keeps a locally modified copy
  (ansible's `apt` module passes `force-confold`), so a server's configuration survives.
- **The unit is left alone.** Unlike `promtool.yml`, which must disable the
  Alertmanager daemon its package enables, HashiCorp's `postinst` does not enable or start
  `vault.service` — it only runs `daemon-reload`. Anything other than `disabled` was put
  there by something else on the host, and turning off a server this playbook did not start
  is not a CLI installer's business. Task 19 reports the state instead of changing it.

This repo ships no Vault server playbook — only the client, here.

A "client-only" install still lays down server scaffolding, because the package does:
a `vault` system user, a self-signed cert under `/opt/vault/tls`, `/opt/vault/data`, a
`vault.service` unit, and `setcap cap_ipc_lock=+ep` on the binary. All of it is inert until
something enables the unit.

### Cleans up a stale apt source

This playbook removes `/etc/apt/sources.list.d/apt_releases_hashicorp_com.list` if
present — left beside the new `.sources` file, apt reads the repository twice and warns
the target is configured multiple times. An old keyring at
`/etc/apt/keyrings/hashicorp-archive-keyring.asc` is left alone: it holds the same key,
byte for byte, and an unused keyring is inert.

The suite is mapped to `noble`: HashiCorp's Artifactory does also publish `resolute` with
identical content, but two entries for one URI under different suites are two repositories
to apt, so `noble` is what this playbook standardizes on.

### The signing key is fetched, not pinned

HashiCorp's packaging key `798AEC654E5C15428C8E42EEAA16FCBCA621E701` **expires
2028-01-09**, so it is fetched each run — `deb822_repository` compares by checksum,
so that stays idempotent — and only its fingerprint is asserted. Pinning today's bytes
would turn the eventual rotation into a signature failure on every host. Same form as
`github-cli.yml`, opposite form to `azure-cli.yml`, whose key does not expire.

### The smoke test formats a policy file

`vault policy fmt` parses and rewrites HCL without contacting a server, so it exercises real
offline work, where every other `vault` subcommand needs an address and a token.
`VAULT_ADDR` is deliberately left unset. The check also proves the package's
`setcap cap_ipc_lock=+ep` does not stop an arbitrary uid from executing the binary.

### Per-user setup

```bash
export VAULT_ADDR=https://<your-vault>:8200
vault login                  # writes ~/.vault-token
vault token lookup           # confirm which identity is active
```

`VAULT_ADDR` is shared, non-secret configuration and the CLI does read it, but no playbook
sets it — that stays a per-account or per-site decision. `VAULT_TOKEN` is a secret and
must never go in `/etc/environment`.

## Replacing the Homebrew installs

If `jira`, `gcx`, `influx` or `vault` were ever installed with Homebrew on this host, the
Homebrew copies may still shadow the system-wide ones these playbooks install:

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

If you remove the Homebrew prefix entirely, list its `bin` and `lib` first — formula
removal does not always catch hand-built binaries or orphaned directories underneath it.
