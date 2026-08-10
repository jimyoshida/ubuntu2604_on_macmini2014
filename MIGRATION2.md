# Multi-User Workstation Cloud CLI Playbook Migration

Policy and procedure for migrating the cloud/service CLI playbooks from `cloud-cli/` to
`_multi-user/cloud-cli/`.

**Status: in progress.** 12 of 13 source playbooks migrated and verified. Waves 2 and 3 are
complete; only `jenkins-cli.yml` (#12) remains, and it is still blocked on wave 1's
`env-tmpl.sh` decision. See [Migration status](#migration-status).

This document is the sequel to [MIGRATION.md](MIGRATION.md), which covered `tool/` →
`_multi-user/tools/` and is complete. Everything there still applies: the
[prerequisites](MIGRATION.md#prerequisites) (inventory, `ubuntu` remote user, passwordless
sudo), the ten [policy](MIGRATION.md#policy) points, the [playbook
skeleton](MIGRATION.md#playbook-skeleton), and the [install mechanism decision
order](MIGRATION.md#install-mechanism-decision-order). This document records only what is
*different* about `cloud-cli/`, plus the per-tool plan.

## Background

`cloud-cli/` was explicitly listed as out of scope in MIGRATION.md, with the note that it
"is genuinely per-identity (credentials, agent configs) and should stay per-user, but
parameterised by an explicit user list instead of `$USER`". That is the crux: unlike `tool/`,
where the goal was simply "get the binary somewhere every account can use it", each of these
playbooks has **two halves that must be separated**:

| Half | Belongs | Example |
| --- | --- | --- |
| The binary and its shared data | root-owned system paths | `/usr/local/bin/aws`, `/usr/lib/google-cloud-sdk` |
| The identity that drives it | per-user `$HOME`, or nowhere at all | `~/.aws/credentials`, `~/.vault-token`, `GH_TOKEN` |

MIGRATION.md's three causes of single-user breakage all recur here, plus two new ones:

1. **Homebrew ownership.** Affects `jira-cli`, `gcx-cli`, `influx-cli`, `vault-cli` — four of
   thirteen, all installed via `brew` as `lookup('env', 'USER')`, two of them via a tap.
2. **Per-user shell profiles.** No playbook here writes `~/.bashrc` today, but several tools
   ship shell completions that a single-user install would have landed in one home directory.
3. **Per-user install prefixes.** `azure-devops-cli.yml` is the sharp case: task 7 runs
   `az extension add` with `become: no`, so the extension lands in the *invoking* account's
   `~/.azure/cliextensions/` and is invisible to every other user, even though the `az` binary
   underneath it is a system-wide apt package.
4. **NEW — install-time `lookup('env', ...)` baked into shared state.** `jenkins-cli.yml`
   renders `JENKINS_URL` from whoever ran the playbook into `/usr/local/bin/jenkins-cli`, a
   file every account executes. `azure-devops-cli.yml` tasks 8–9 write `AZURE_DEVOPS_ORG` /
   `AZURE_DEVOPS_PROJECT` into the invoking account's `~/.azure/config`. In both cases one
   person's environment silently becomes either everyone's default or exactly one person's.
5. **NEW — secrets.** `cloud-cli/env-tmpl.sh` is a template for eight tokens
   (`JENKINS_API_TOKEN`, `JIRA_API_TOKEN`, `INFLUX_TOKEN`, `VAULT_TOKEN`, `GRAFANA_TOKEN`,
   `AZURE_DEVOPS_EXT_PAT`, …). MIGRATION.md policy point 3 sends environment variables to
   `/etc/environment` — which is world-readable and shared. Applied naively to this directory
   that policy would publish every user's tokens to every other account on the box. See
   [Policy amendments](#policy-amendments).

## Scope

| | |
| --- | --- |
| Source | `cloud-cli/*.yml` (13 playbooks) + `cloud-cli/env-tmpl.sh` |
| Target | `_multi-user/cloud-cli/*.yml` |
| Applies to | New multi-user workstation builds |
| Control node | Ubuntu 24.04 (ansible-core **2.16**) **or** Ubuntu 26.04 (ansible-core 2.20) |
| Targets | Ubuntu 26.04 (`ws01`, `ws02`), Python 3.14 |

**On the control node version.** Both control nodes are in use and both must work, so
**2.16 is the floor**: a playbook may use nothing that postdates it, and must still be correct
on 2.20. Do not take the drafting machine's `ansible --version` as the constraint — the 26.04
checkouts carry 2.20, and a module or filter that works there may simply not exist on a 24.04
control node. Everything this plan calls for clears the floor;
`ansible.builtin.deb822_repository` ([A5](#policy-amendments)) is the only module newer than
the ones `_multi-user/tools/` already uses, and it landed in 2.15. Confirm before adopting
anything else:

```bash
ansible --version                       # on the control node, not the target
ansible-doc <module> | grep -i "added in"
```

One thing to watch that no `grep` will catch, and the one place the two control nodes may not
behave alike: ansible-core 2.16's *target* Python support matrix tops out well below the 3.14
that Ubuntu 26.04 ships, while 2.20's covers it. The `tool/` migration's eleven playbooks ran
clean against `ws01`/`ws02`, so at least one of the two combinations works in practice — but
that does not say which control node produced those runs. Run one wave-2 playbook from a
**24.04** control node early to establish that the lower half of the support matrix holds,
rather than discovering an interpreter incompatibility in wave 4. If it does not hold, that is
a finding about the 24.04 control node, not about any individual playbook — record it here and
decide whether 24.04 stays supported.

**On the target naming.** `_multi-user/tools/` needed the plural to avoid colliding with the
`tool/` it replaces. No such collision exists here — `_multi-user/cloud-cli/` and `cloud-cli/`
are distinguished by their parent — so keep the source directory's name. The leading
underscore on `_multi-user/` still means "staging", same as before.

**Out of scope:**

- `{core,container,ai-agent,services,gui-tools,media}/` — still a separate question.
- `cloud-cli/*` itself stays in place until the new build is proven, same as `tool/` did.
- Deploying any of the *servers* these CLIs talk to (Jenkins, Vault, InfluxDB, Alertmanager).
  Every playbook here installs a client only, and that stays true after migration.

## Policy amendments

MIGRATION.md's ten points hold. These five amendments (A1–A5) resolve the cases they do not
cover. Where an amendment tightens a numbered policy point, that point's number is given.

**A1. Secrets never leave `$HOME`. (amends point 3)**
Split what MIGRATION.md treats as one category:

| Kind | Example | Destination |
| --- | --- | --- |
| Shared, non-secret endpoint config | `JENKINS_URL`, `GRAFANA_SERVER`, `INFLUX_HOST`, `VAULT_ADDR`, `AZURE_DEVOPS_ORG` | `/etc/environment` or `/etc/profile.d/<tool>.sh`, set from an explicit play var |
| Per-identity, non-secret | `AWS_PROFILE`, `CLOUDSDK_CORE_PROJECT` | per-user `$HOME`; not set by these playbooks |
| Secret | every `*_TOKEN`, `*_PAT`, `*_API_TOKEN` | per-user `$HOME` only, mode `0600`; **never** `/etc`, never a play var, never committed |

A playbook that would need a secret to complete is mis-designed: installation must not require
credentials. If verification appears to need one, the verification is testing the wrong thing —
see A4 below.

**A2. Endpoint config comes from a play var, not `lookup('env', ...)`. (amends point 5)**
Replace every `lookup('env', 'X')` with a `vars:` entry overridable by `-e`, exactly as tool
versions already are. `-e jenkins_url=http://ci.example.com:8080` is reproducible and shows up
in the run record; `export JENKINS_URL=...` on one operator's shell does not.

**A3. Per-identity setup is out of the playbook, into the README.**
`az devops configure --defaults`, `jira init`, `influx config create`, `gcloud auth login`,
`gh auth login` are per-person, interactive, and credential-bearing. Drop these tasks; keep the
post-install `debug` message that tells each user the command to run for themselves. Where a
default genuinely should apply to everyone (a default Jenkins URL, a default DevOps org),
express it as A1 shared config, not as a write into one account's config file.

**A4. Verification proves reachability, not authentication. (amends point 9)**
Point 9's `setpriv --reuid=65534` regression guard still applies, but almost none of these
tools can do useful work unauthenticated. The guard therefore asserts: *an arbitrary uid can
execute the binary, load its shared libraries/extensions/JARs, and reach its own
zero-configuration code path.* Concretely, prefer in this order:

1. Offline real work — `promtool check config`, `amtool check-config`, `tofu fmt -check` on a
   file the playbook writes. Strongest guard; use it where the tool allows it.
2. A subcommand that inspects the install itself — `az extension show --name azure-devops`,
   `gcloud version`, `aws configure list`.
3. `--version` / `version` alone. Weakest; acceptable only where 1 and 2 do not exist.

Two mechanics that bit `tool/` and will bite harder here:

- **Give the smoke test a writable `HOME`.** `az`, `gcloud`, `aws`, and `influx` all write
  state on first invocation and fail outright when `HOME` is unset or unwritable. Run them as
  `setpriv ... env HOME=<mktemp -d under /var/tmp>` and remove the directory afterwards. Use
  `/var/tmp`, not `/tmp` — MIGRATION.md's `grype-syft` finding (`/tmp` is a size-capped tmpfs
  on `ws01`/`ws02`) applies to anything that downloads or caches.
- **Leave discovery variables unset.** Do not set `AZURE_EXTENSION_SYS_DIR`, `CLOUDSDK_CONFIG`,
  or `AZURE_CONFIG_DIR` in the smoke test. The zero-configuration path is the thing under test.

**A5. Vendor apt repositories get one shared convention. (amends point 1)**
Seven of thirteen tools install from a vendor apt repository, and three of those repositories
are already configured by playbooks outside this directory (`services/vault.yml` added the
HashiCorp repo before it was deleted — its `.list` survives on hosts it ran on; `core/` and
`container/` add others). Every migrated playbook must therefore:

- Use `ansible.builtin.deb822_repository` (added in ansible-core 2.15, so it clears the 2.16
  floor; the module handles `Signed-By` inline) instead of `get_url` + a `shell`
  dearmor + `apt_repository`. The current `shell: gpg --dearmor` tasks report `changed` on
  every run and are the main source of noise in these playbooks. Two mechanics the module
  documents: it needs **`python3-debian` on the target**, so add it to each playbook's task 1
  prerequisites, and it does **not** refresh the apt cache — follow it with an
  `ansible.builtin.apt` task doing `update_cache` conditioned on the repository task's
  `changed` state.
- Take architecture from `ansible_architecture` (policy point 8) rather than the hardcoded
  `arch=amd64` that five playbooks carry today.
- Map the distro codename where the vendor does not publish one for the target release. The
  source `azure-cli.yml` already does this (`resolute`/`plucky` → `noble`); the same is needed
  for the HashiCorp repo. Factor it into an identical `vars:` block in each playbook rather
  than a role — self-contained playbooks is still policy point 10.
- Match the keyring path and `sources.list.d` filename any *existing* repo-adding playbook
  uses, so the two do not fight. Check before writing:
  ```bash
  grep -rn "keyrings\|deb \[" --include=*.yml . | grep -v '^_multi-user/'
  ```

## Per-tool identity state

What stays per-user after migration. This is the table to check a playbook against: if a
migrated playbook touches anything in the "Per-user state" column, it is wrong.

| Tool | Per-user state | Non-secret env (A1 shared) | Secret env (A1 per-user) |
| --- | --- | --- | --- |
| `aws` | `~/.aws/{config,credentials}` | — | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` |
| `az` | `~/.azure/` | — | — (uses `az login` token cache) |
| `gcloud` | `~/.config/gcloud/` | — | — (uses `gcloud auth` token store) |
| `gh` | `~/.config/gh/hosts.yml` | — | `GH_TOKEN` |
| `glab` | `~/.config/glab-cli/config.yml` | — | `GITLAB_TOKEN` |
| `tofu` | `~/.terraform.d/` | — | provider credentials (per provider) |
| `promtool` / `amtool` | `~/.config/amtool/config.yml` (optional) | — | — |
| `jira` | `~/.config/.jira/.config.yml` | — (**not** `JIRA_URL`/`JIRA_LOGIN` — see below) | `JIRA_API_TOKEN` (also reads `JIRA_AUTH_TYPE`, `JIRA_CONFIG_FILE`) |
| `gcx` | `~/.config/gcx/`, `~/.local/state/gcx/`, `./.gcx.yaml` | `GRAFANA_SERVER` ✓verified | `GRAFANA_TOKEN` |
| `influx` | `~/.influxdbv2/configs` | `INFLUX_HOST`, `INFLUX_ORG` ✓verified | `INFLUX_TOKEN` |
| `vault` | `~/.vault-token` | `VAULT_ADDR` ✓verified | `VAULT_TOKEN` |
| `jenkins-cli` | none | `JENKINS_URL` | `JENKINS_USER_ID`, `JENKINS_API_TOKEN` |
| `az devops` | `~/.azure/azuredevops/config` defaults | `AZURE_DEVOPS_EXT__DEFAULTS_ORGANIZATION`, `AZURE_DEVOPS_EXT__DEFAULTS_PROJECT` (double underscore — see below) | `AZURE_DEVOPS_EXT_PAT` |

`cloud-cli/env-tmpl.sh` mixes all three columns into one file. Its successor should ship as two
pieces: the shared, non-secret half applied by the playbooks per A1, and a per-user
`~/.config/cloud-cli/env.sh` template (mode `0600`, sourced by the user, gitignored) for the
rest. Decide this before migrating `jenkins-cli.yml`, the first playbook that needs it.

**The `az devops` row was wrong, and wrong in the way that matters.** `AZURE_DEVOPS_ORG` and
`AZURE_DEVOPS_PROJECT` were carried into this table from the source playbook, where they were
inputs to the *playbook* — read with `lookup('env', ...)` and fed to
`az devops configure --defaults`. The CLI itself never reads them. The extension builds its
knack config with `config_env_var_prefix = 'AZURE_DEVOPS_EXT_'`
(`azext_devops/dev/common/const.py`) and knack appends another `_` before
`{section}_{option}`, so the only environment override for `defaults.organization` is
`AZURE_DEVOPS_EXT__DEFAULTS_ORGANIZATION`. Verified on the target, as uid 65534 with an empty
`HOME`: with that name `az devops project list` gets past organization resolution and fails on
credentials; with `AZURE_DEVOPS_ORG`, or with `AZURE_DEFAULTS_ORGANIZATION` (the azure-cli
*core* spelling, which `az config get defaults.organization` does honour), it still fails with
`--organization must be specified`.

The general lesson for the remaining A1 shared-config rows: **a variable name taken from a
source playbook's `lookup('env', ...)` is not evidence that the tool reads it.** Half of these
names were the old playbooks' own inputs. Confirm each against the tool before writing it to
`/etc/environment`, and prefer asserting it in the playbook — a shared default under a name
the tool ignores is invisible, because the variable is set, `/etc/environment` looks correct,
and every user still gets an error. `azure-devops-cli.yml` task 20a is the pattern: run the
tool as an unprivileged uid with the variable set and assert that the "not configured" error
is *not* what comes back.

**Wave 3 checked its four rows against the binaries, and found one more wrong.** Method: run
the tool with the variable set and with a plausible near-miss name as a negative control, and
compare the failure.

- `GRAFANA_SERVER` — **read.** With it set, `gcx config check` gets past
  `Invalid configuration: server is required` and fails on credentials instead; with
  `GRAFANA_ENDPOINT` set instead it still reports `server is required`.
- `INFLUX_HOST`, `INFLUX_ORG` — **read.** `influx ping` requests the host named in
  `INFLUX_HOST` (default `http://localhost:8086` without it), and `influx bucket list` sends
  `?org=<INFLUX_ORG>`.
- `VAULT_ADDR` — **read.** `vault status` queries the address given (default
  `https://127.0.0.1:8200`).
- `JIRA_URL`, `JIRA_LOGIN` — **not read, like `AZURE_DEVOPS_ORG` before them.** With both set,
  `jira issue list` still exits 1 with "The tool needs a Jira API token to function". The
  binary's `JIRA_*` strings are `JIRA_API_TOKEN`, `JIRA_AUTH_TYPE`, `JIRA_BROWSER`,
  `JIRA_CONFIG_FILE`, `JIRA_EDITOR` — no server or login variable at all; jira-cli takes both
  from `~/.config/.jira/.config.yml`, written by `jira init`. They were the source playbook's
  own inputs, used only to interpolate an instruction into a `debug` message.

That is two of the seven names in this table wrong, from two different source playbooks, which
makes the pattern rather than the exception the thing to plan for. The four verified ones are
still not written to `/etc/environment` by any playbook: being a name a tool reads is
necessary, not sufficient — there also has to be a shared endpoint worth naming, and for
Grafana/InfluxDB/Vault this repo has none.

## Per-tool migration plan

Mechanism numbers refer to MIGRATION.md's [decision
order](MIGRATION.md#install-mechanism-decision-order).

| # | Playbook | Today | Target mechanism | Principal work |
| --- | --- | --- | --- | --- |
| 1 | `github-cli.yml` | vendor apt repo | (2) unchanged — `cli.github.com` | A5 cleanup; arch from facts; pin + version-aware guard; smoke test |
| 2 | `opentofu.yml` | vendor apt repo (2 keys) | (2) unchanged — `packages.opentofu.org` | A5 cleanup ×2 keys; pin; `tofu fmt -check` smoke test |
| 3 | `prometheus-cli.yml` | apt | (1) unchanged | pin both packages; keep the alertmanager-daemon disable; `promtool`/`amtool check-config` smoke tests |
| 4 | `azure-cli.yml` | vendor apt repo | (2) unchanged — `packages.microsoft.com` | A5 cleanup; keep the codename map; pin; smoke test with writable `HOME` |
| 5 | `gcloud-cli.yml` | vendor apt repo | (2) unchanged — `packages.cloud.google.com` | A5 cleanup; pin; drop the `GOOGLE_CLOUD_PROJECT`/`LOCATION` env lookups per A2/A3 |
| 6 | `gitlab-cli.yml` | floating "latest" `.deb` | (3)/(2) pinned `.deb` from the GitLab release API | pin a version (today it installs whatever is newest, silently); verify against `checksums.txt`; arch from facts |
| 7 | `aws-cli.yml` | vendor zip + `install` | (3) same installer, hardened — see note | pin version in the URL; verify AWS's GPG signature; arch from facts; replace the `creates:` guard |
| 8 | `jira-cli.yml` | **brew + tap** | (3) GitHub release tarball → `/usr/local/bin/jira` | de-brew; `checksums.txt`; **asset arch is `x86_64`/`arm64`, not `amd64`**; install completions to `/etc/bash_completion.d` |
| 9 | `gcx-cli.yml` | **brew + tap** | (3) GitHub release tarball → `/usr/local/bin/gcx` | de-brew; `gcx_<v>_checksums.txt`; drop the `GRAFANA_SERVER` env lookup per A2 |
| 10 | `influx-cli.yml` | **brew** | (3) `dl.influxdata.com` tarball → `/usr/local/bin/influx` | de-brew; **not on GitHub releases** — see note; `.sha256` sibling has a path-prefixed entry |
| 11 | `vault-cli.yml` | **brew + tap** | (2) HashiCorp apt repo | de-brew; **overlaps `services/vault.yml`** — see note |
| 12 | `jenkins-cli.yml` | already system-wide | (3)-ish, unchanged shape | A2: `jenkins_url` becomes a play var; wrapper reads a shared default from `/etc`, not from install-time `$JENKINS_URL`; unprivileged smoke test instead of `become: no` |
| 13 | `azure-devops-cli.yml` | apt `az` + **per-user extension** | (2) + `az extension add --system` | the real work of this migration — see note |

### Notes on the four that need a decision

**`aws-cli.yml` (#7) — installer, not apt, but check the target first.** Ubuntu 26.04's
`universe` now carries `awscli 2.31.35-1`, which is genuinely AWS CLI **v2** and not the old
v1 Python package, so decision-order point 1 arguably applies. Recommend **keeping the
official installer** anyway: it is what AWS supports, universe packages typically freeze for
an LTS lifetime while `aws` ships weekly, and the installer already targets root-owned
`/usr/local/aws-cli` with symlinks in `/usr/local/bin` — it is multi-user safe today, so this
is hardening rather than relocation. Revisit if `apt-cache policy awscli` on the target is
within a few releases of upstream at migration time. Either way the current playbook's
`creates: /usr/local/bin/aws` guard has to go: it makes `--update` unreachable, so the version
never moves (policy point 6).

**`influx-cli.yml` (#10) — the release lives off GitHub.** `influxdata/influx-cli`'s GitHub
releases carry **no assets**; binaries are published at
`https://dl.influxdata.com/influxdb/releases/influxdb2-client-<version>-linux-<arch>.tar.gz`
with a `.sha256` sibling. Two traps: the v2.8.0 release notes announce a rename to
`influxdb2-cli` while the published asset is still named `influxdb2-client-*` (confirm the
actual filename at pin time, both spellings), and the `.sha256` file's entry is
`<hash>  /root/project/packages/<file>` — a build-path prefix, so the anchored match pattern
must allow it. This is the same class of trap as the `bin/` prefix MIGRATION.md's step 5
warns about.

**`vault-cli.yml` (#11) — collides with `services/vault.yml`. Resolved as (a); two of the
premises below turned out to be wrong — see [wave 3](#wave-3-jira-cli-gcx-cli-influx-cli-vault-cli).** Both would install the same
`vault` apt package from the same HashiCorp repository; `services/vault.yml` already adds that
repo (keyring at `/etc/apt/keyrings/hashicorp-archive-keyring.asc`). Decide one of:

- (a) **Recommended** — keep a CLI-only playbook under `_multi-user/cloud-cli/`, reusing
  `services/vault.yml`'s exact keyring path and repo filename per A5 so the two are idempotent
  against each other, and document that running both is safe and installs one package.
- (b) Declare `vault-cli.yml` redundant and let `services/` own Vault entirely.

Whichever is chosen, check on the target whether HashiCorp's `.deb` enables `vault.service` on
install. If it does, a CLI-only playbook must stop and disable it, exactly as
`prometheus-cli.yml` already does for `prometheus-alertmanager`. Also note the HashiCorp repo
publishes for `noble`, not `resolute` — the A5 codename map is required, not optional.

> **Outcome (2026-08-10).** (a), and then the collision dissolved: `services/vault.yml` was
> **deleted** rather than migrated, together with the local Vault server it had deployed
> (service stopped and disabled; `/opt/vault`, `/etc/vault.d`, the `vault` system user and
> the `~/.bashrc` block removed; storage deleted without a backup). It deployed a server
> nothing in this repo used, in exactly the shape this migration removes — a `0.0.0.0:8200`
> listener with `tls_disable = 1`, and `VAULT_ADDR` appended to whoever ran it — and
> deploying servers is out of scope here, so there was nothing to migrate it into.
> `vault-cli.yml` is now the only Vault playbook in the repo and keeps both its `noble` pin
> and its removal of the old `.list`, because hosts the deleted playbook ran on still carry
> that file. The two premises in the paragraph above are both wrong: the `.deb` does **not**
> enable `vault.service`, and HashiCorp does publish `resolute`. See
> [wave 3](#wave-3-jira-cli-gcx-cli-influx-cli-vault-cli).

**`azure-devops-cli.yml` (#13) — the one genuinely broken install.** `az extension add`
without `--system` writes to `$HOME/.azure/cliextensions`, so today only the account that ran
the playbook has the extension. `az extension add --system` installs into an
`azure-cli-extensions` directory under the CLI's Python environment (overridable via
`AZURE_EXTENSION_SYS_DIR`), which is root-owned and readable by everyone — this is confirmed
present in the `az` version the Microsoft repo currently ships. Plan:

- Install `azure-cli` per #4, then `az extension add --system --name azure-devops` as root,
  pinned with `--version` and guarded on `az extension show --name azure-devops --query version`
  (policy point 6). Note `az extension list-versions --name azure-devops` reports a "max
  compatible version" for the installed `az`; pin to that, not to the newest published.
- Drop tasks 8 and 9 (`az devops configure --defaults`) per A3 — they configure one account.
  If a shared default org/project is wanted, set `AZURE_DEVOPS_ORG` / `AZURE_DEVOPS_PROJECT`
  in `/etc/environment` from play vars per A1/A2, and say so in the README.
- Smoke test as uid 65534 with a writable `HOME` and `AZURE_EXTENSION_SYS_DIR` **unset**, so
  what gets proven is that a fresh account discovers the system extension by default. This is
  the single most important verification in this migration: it is exactly the regression the
  source playbook has.

## Order of work

Four waves, each ending in a commit and a status-table update:

1. **Decisions first (no playbooks).** Settle the `env-tmpl.sh` split (A1), the
   `vault-cli`/`services/vault.yml` overlap, and the shared A5 vendor-repo block. These three
   are referenced by nearly every playbook; deciding them mid-migration means rewriting
   earlier ones.
2. **Vendor-repo and apt playbooks — #1–#7. Done.** Already system-wide, so this was
   correctness work: A5 cleanup, pins, version-aware guards, smoke tests. It established the
   house style for the wave that follows, and settled the shared A5 vendor-repo block that
   wave 1 left open — including the two key-pinning forms and the four `--check` defects
   recorded under [Verification status](#verification-status).
3. **De-brew — #8–#11. Done.** The reach work: four tools moved out of one account's
   `/home/linuxbrew` into root-owned system paths. Each was an independent tool with an
   independent version pin, and the wave needed no shared decision that wave 2 had not
   already settled.
4. **The configured ones — #12–#13.** Both depend on wave 1's decisions and on wave 2 (#13
   needs `azure-cli.yml` finished; #12 needs the shared-config mechanism).

## Procedure

MIGRATION.md's [ten-step procedure](MIGRATION.md#procedure) applies unchanged, with three
additions:

- **After step 1 (read the source playbook),** fill in that tool's row of the [per-tool
  identity state](#per-tool-identity-state) table and confirm the migrated playbook touches
  nothing in the per-user column.
- **Before step 6 (write the playbook),** check the target's apt for a vendor-repo collision
  and for the real candidate version. MIGRATION.md's `shellcheck` finding — a pin taken from
  a local apt cache that did not exist on the target — is the failure mode; with seven vendor
  repositories in play here the collision risk is new on top of it:
  ```bash
  cd _multi-user
  ansible -m shell -a 'cat /etc/os-release; ls /etc/apt/sources.list.d/' <host>
  ansible -m shell -a 'apt-cache policy <package>' <host>
  ```
- **In step 8 (README),** state the per-user setup command each account must run for itself
  (A3), and which environment variables are shared versus secret (A1).

## Migration status

| Source playbook | Old mechanism | Target mechanism | Pinned | Status |
| --- | --- | --- | --- | --- |
| `github-cli.yml` | vendor apt repo | vendor apt repo, A5 cleanup | 2.97.0 | Verified (localhost) |
| `opentofu.yml` | vendor apt repo (2 keys) | vendor apt repo, A5 cleanup, 1 key | 1.12.5 | Verified (localhost) |
| `prometheus-cli.yml` | apt | apt, pinned | promtool 2.53.5+ds1-3, alertmanager 0.28.1+ds-3 | Verified (localhost) |
| `azure-cli.yml` | vendor apt repo | vendor apt repo, A5 cleanup | 2.89.0-1~noble | Verified (localhost) |
| `gcloud-cli.yml` | vendor apt repo | vendor apt repo, A5 cleanup | 579.0.0-0 | Verified (localhost) |
| `gitlab-cli.yml` | floating latest `.deb` | pinned `.deb` + checksum | 1.112.0 | Verified (localhost) |
| `aws-cli.yml` | vendor zip installer | same installer, pinned + signature-verified | 2.36.17 | Verified (localhost) |
| `jira-cli.yml` | brew + tap | release tarball → `/usr/local/bin` | 1.7.0 | Verified (localhost) |
| `gcx-cli.yml` | brew + tap | release tarball → `/usr/local/bin` | 1.0.0 | Verified (localhost) |
| `influx-cli.yml` | brew | `dl.influxdata.com` tarball → `/usr/local/lib` + symlink | 2.8.0 | Verified (localhost) |
| `vault-cli.yml` | brew + tap | HashiCorp apt repo, A5 cleanup | 2.0.4-1 | Verified (localhost) |
| `jenkins-cli.yml` | system-wide + `$JENKINS_URL` | unchanged shape; URL from a play var | n/a | Planned |
| `azure-devops-cli.yml` | apt `az` + per-user extension | apt `az` + `az extension add --system` | az 2.89.0-1~noble, ext 1.0.6 | Verified (localhost) |

Versions are deliberately left `TBD`: MIGRATION.md's step 3 requires checking upstream at the
time each playbook is written, and the [upstream survey](#upstream-survey-2026-08-06) below
will be stale by then.

`aws-cli.yml` was taken first, ahead of its position in wave 2. Nothing depends on it and it
depends on none of wave 1's three decisions — it sets no environment variable, shares no vendor
apt repository, and configures no identity — so the ordering above is unaffected.

### Verification status

Rows marked "Written, not yet run" have been YAML-validated, syntax-checked, and reviewed
against the policy, but **not executed against a target host**. Treat them as unverified until
someone runs `ansible-playbook cloud-cli/<tool>.yml -e host=<host>` and updates the table.
Rows marked "Verified" completed with `failed=0` against the listed host, and re-ran
idempotently.

`aws-cli.yml` is verified against `localhost` — this repo's own workstation, provisioned in
place via an `ansible_connection=local` inventory entry rather than over SSH — and **not** yet
against `ws01`/`ws02`. Two caveats on what that does and does not establish: the run exercised
ansible-core 2.20, so it says nothing about the 2.16 control node, and a local connection never
touches the SSH/`remote_user` path. What it does establish is the whole install: signature
verification, the install itself, world-readable modes, and the unprivileged check. Re-running
is idempotent — `ok=10 changed=2 skipped=10`, the two changes being the scratch `HOME` the
smoke test creates and removes, the same churn `tools/kube-score.yml` has for its smoke
manifest.

`aws-cli.yml` needed a fix discovered only at run time: **`gpg` will not create a missing
`--homedir` under `--batch`**. Task 8 imported the signing key into a throwaway keyring inside
the staging directory, and failed with `no writable keyring found: Not found` because nothing
had created that subdirectory — the failure names the keyring file, not the missing directory,
so it reads like a gpg configuration problem rather than a mkdir that never happened. The
playbook now creates the `gnupg` subdirectory explicitly at mode `0700` (`0700` also being
required to avoid gpg's unsafe-permissions warning on every invocation). This will recur in
every playbook that verifies a signature in a scratch keyring rather than against apt's
keyring, so create the homedir first.

Post-run verification independent of the playbook's own checks: `/usr/local/aws-cli` is
root-owned with no non-world-readable file in the tree, `/var/tmp` holds no staging or
scratch-`HOME` leftovers, and `aws --version` runs under
`setpriv --reuid=65534 --regid=65534 --clear-groups` with `HOME=/nonexistent`.

`azure-cli.yml` and `azure-devops-cli.yml` are verified against `localhost`, with the same two
caveats as `aws-cli.yml`: ansible-core 2.20 only, and no SSH/`remote_user` path. Both re-run
idempotently — `ok=11 changed=2 skipped=4` and `ok=19 changed=4 skipped=7`, every change being
a scratch `HOME` created and removed. `--check` was exercised first on both and wrote nothing:
no `.sources` file, no package change, no scratch directories left behind.

`azure-devops-cli.yml` was taken out of wave-4 order, immediately after `azure-cli.yml` (#4),
its only real dependency. It does not in fact need wave 1's `env-tmpl.sh` decision: its shared
half is two non-secret variables written straight to `/etc/environment` per A1/A2, and its
secret (`AZURE_DEVOPS_EXT_PAT`) is simply not touched — there is nothing for a per-user
template to hold. `jenkins-cli.yml` (#12) still blocks on that decision.

Five findings from these two, in rough order of how much they will affect the remaining
playbooks:

- **A1 shared-config variable names cannot be taken on trust.** The largest finding, recorded
  in full under [per-tool identity state](#per-tool-identity-state): `AZURE_DEVOPS_ORG` is not
  a variable the CLI reads, and neither is the plausible-looking
  `AZURE_DEFAULTS_ORGANIZATION`. Six rows of that table still carry unverified names.
- **`az extension add --system` writes under the CLI's bundled Python version**, at
  `/opt/az/lib/python3.<minor>/site-packages/azure-cli-extensions`, and that minor version
  moves with the package: `2.86.0-1~noble` bundles Python 3.13, `2.89.0-1~noble` bundles 3.14.
  An extension installed before such an upgrade is orphaned, silently. `azure-devops-cli.yml`
  resolves the path from `az extension show --query path` at run time rather than hardcoding
  it, and because its guard compares the *reported* extension version, an orphan reads as
  uninstalled and is reinstalled on the next run — one run does the package and the extension,
  in that order. Any playbook installing a plugin into another tool's private prefix has this
  shape; resolve the prefix at run time, as `tools/markdownlint.yml` does for npm.
- **`az` needs a writable `HOME` and forks a telemetry uploader that outlives the command.**
  A4 already called for the writable `HOME` (`az` aborts with `PermissionError` on
  `/nonexistent`); what it did not anticipate is that the uploader **recreates the scratch
  `HOME` after the playbook removes it**, leaving a `nobody`-owned directory in `/var/tmp`.
  Verified both ways: with `AZURE_CORE_COLLECT_TELEMETRY=0` the directory stays gone, without
  it the directory is back within seconds. This is not one of A4's discovery variables and
  setting it does not weaken the test — `AZURE_EXTENSION_SYS_DIR` and `AZURE_CONFIG_DIR` are
  left unset, which is what A4 is about. Expect the same class of leftover from any tool with
  opt-out telemetry (`gcloud` in particular).
- **A5's `deb822_repository` works as planned, with one cosmetic wart.** The inline
  `Signed-By` route removes the `shell: gpg --dearmor` task entirely, and the repository task
  now reports `ok` rather than `changed` on every run, which was A5's whole objective. The
  wart: the module serialises its own `install_python_debian` option into the file as
  `Install-Python-Debian: no`. apt ignores it — `apt-get update` hits the repository with no
  warning — but it will appear in all seven A5 playbooks' `.sources` files.
- **A superseded `.list` and a new `.sources` for the same repository do collide.** Both
  Azure playbooks remove `/etc/apt/sources.list.d/azure-cli.list`, which the two source
  playbooks wrote; left in place, apt reads the repository twice and warns that the target is
  configured multiple times. The stale keyring (`/etc/apt/keyrings/microsoft.gpg`) is left
  alone as inert. This applies to every migrated vendor-repo playbook whose predecessor has
  been run on the same host — which is the case on `localhost` for all seven, though not on a
  fresh `ws01`/`ws02` build. A5's `grep` catches the in-repo convention; it does not catch
  what is already on the host, so check `ls /etc/apt/sources.list.d/` on the target too.

Also confirmed while writing these: Microsoft publishes `noble` but neither `resolute` nor
`plucky` for `/repos/azure-cli` (both 404), so A5's codename map is required, not optional —
and the suite is embedded in the package version (`2.89.0-1~noble`), so the pin is composed
from version + mapped suite rather than written out, and a suite change carries the pin with
it. The `azure-cli` package also ships `/etc/bash_completion.d/azure-cli` itself, so `az` does
**not** belong on the list of tools blocked on the `/etc/profile.d` bootstrap.

### Wave 2 (`github-cli`, `opentofu`, `prometheus-cli`, `gcloud-cli`, `gitlab-cli`)

All five verified against `localhost`, `failed=0`, with the same caveats as everything
else here: ansible-core 2.20 only, and a local connection exercises neither the 2.16
control node nor the SSH path. Re-runs are identical to first runs task for task, every
`changed` being a scratch directory created and removed. Post-run checks independent of
the playbooks: `gh 2.97.0`, `tofu 1.12.5`, `gcloud 579.0.0`, `glab 1.112.0`,
`promtool 2.53.5+ds1`, `amtool 0.28.1+ds`; `apt-get update` warns about nothing; the
Alertmanager daemon is `disabled`/`inactive`; `/var/tmp` holds no leftovers.

**A5 now has two forms, and the choice is not stylistic.** Where a vendor publishes a
single armored key with no expiry, it is pinned by content, inline in `Signed-By`
(`azure-cli`, `opentofu`, `gcloud-cli`): the bytes are the trust anchor, and a rotation
fails apt's Release check loudly. Where that does not hold, the key is fetched by URL and
its **fingerprint** pinned and asserted instead (`github-cli`). The rule to apply to the
remaining playbooks:

> Pin the fingerprint always. Pin the key bytes too, only when the key has no expiry.

`github-cli` is the case that forces the distinction, and it is not hypothetical: GitHub
publishes a *binary* keyring holding two keys, and the one currently signing the
repository (`2C6106201985B60E6C7AC87323F3D4EA75716059`) **expires 2026-09-05** — about
four weeks after this was written. A pinned copy would simply stop working. The playbook
therefore fetches each run (the module compares by checksum, so this is still idempotent)
and asserts the *non-expiring successor* `7F38BBB59D064DBCB3D84D725612B36462313325`, which
survives the rotation. Asserting the expiring key instead would convert a routine rotation
into a failed run. This is the same lesson as `aws-cli.yml`'s expired-keyserver finding
seen from the other side: **key expiry is part of the pinning decision, not a detail.**

**`opentofu.yml` installs one key where the source playbook installed two.** The source put
both `get.opentofu.org/opentofu.gpg` and the packagecloud repository key in `signed-by`.
Verified directly against the published `InRelease`: it is signed by subkey
`59D41234F9F7AFD007143F6A70DF59811A8B9109` of the packagecloud key, and the other key's own
user ID says it signs OpenTofu **providers**. A key that signs nothing apt reads does not
belong in `Signed-By`. Worth checking wherever a source playbook lists more than one key —
it is a plausible-looking way to be wrong.

**Three distinct `--check` defects, all in the same family: a task that is skipped, or
half-skipped, feeding a task that is not.** MIGRATION.md's step 10 says `--check` is not a
meaningful dry run for these playbooks, and that remains true of the install itself — but
"not meaningful" and "fails with a misleading error" are different things, and all three of
these produced the latter. Every wave-2 and wave-4 playbook is now `failed=0` under
`--check`, both on a host that already has the pinned version and on one that does not.

- **`chdir` is validated before check mode skips the task.** `opentofu.yml`'s smoke tests
  set `chdir` to a scratch directory an earlier task creates. `command` is skipped under
  `--check`, so the task should never run — but the action validates `chdir` first and the
  dry run dies on `Unable to change directory before execution`. Fixed by giving the
  create and remove tasks `check_mode: false`, so the throwaway directory really exists for
  the length of the run. Applies to any `command` with `chdir` — `tools/trivy.yml` has the
  same shape.
- **`get_url` is not skipped under `--check`; it validates its destination.**
  `gitlab-cli.yml`'s download failed a dry run with `Destination ... does not exist`,
  naming the staging directory that `--check` had not created. Guarded with
  `not ansible_check_mode`, along with the `.deb` install that follows it.
- **`uri` *is* skipped, and registers nothing.** `gitlab-cli.yml` resolves its checksum
  from the release's `checksums.txt`; skipped, that fetch left an empty checksum, which the
  next guard reported as *"checksums.txt has no entry for this asset"* — a dry run accusing
  a perfectly good version pin of not existing. Given `check_mode: false` (fetching a
  published checksums file changes nothing), `--check` now genuinely validates the pin
  against upstream without downloading or installing: the most useful dry run in this
  directory.

**The vendor-repo playbooks had a fourth, shared `--check` defect**, found the same way and
fixed in all five including the two wave-4 ones: on a host that does not yet have the
repository, the repository task reports `changed` without writing, so apt has no candidate
and the pinned install fails outright instead of simulating. The install task now carries
`not (ansible_check_mode and <repo>.changed)`. Where the repository *is* already
configured, it still runs under `--check`, so a dry run keeps showing what apt would do.

`aws-cli.yml` turned up one thing worth carrying forward to the other playbooks: **AWS's
signing key is expired at the public keyservers.** `keyserver.ubuntu.com` serves a
self-signature for `FB5DB77FD5C118B80511ADA8A6310ACC4672475C` that `gpg` reports as expired on
2026-07-07, while the copy in AWS's installation documentation carries an extended expiry of
2027-07-01 — same key, same fingerprint, different self-signature. A playbook that had taken
the convenient route of pulling the key from a keyserver would fail signature verification a
month after that expiry, for reasons that look nothing like a stale key. Verified end to end
before writing the playbook: the documented key validates the real `2.36.17` installer
signature, `gpg --verify` exits 0 on a good signature (the "not certified with a trusted
signature" warning does not change the exit status) and 1 on a tampered file, so the exit code
is a sound gate. Where a vendor publishes a key only as documentation prose, pin it in the
playbook and assert the fingerprint after import.

### Wave 3 (`jira-cli`, `gcx-cli`, `influx-cli`, `vault-cli`)

All four verified against `localhost`, `failed=0`, with the same caveats as everything else
here: ansible-core 2.20 only, and a local connection exercises neither the 2.16 control node
nor the SSH path. Re-runs are idempotent — `ok=14 changed=2` for `jira-cli`, `gcx-cli` and
`influx-cli`, `ok=17 changed=3` for `vault-cli` — every `changed` being the scratch `HOME`
created and removed (plus, for `vault-cli`, the policy file written inside it). `--check` was
exercised first on all four and wrote nothing. Post-run checks independent of the playbooks:
`jira 1.7.0`, `gcx 1.0.0`, `influx` symlinked to `2.8.0`, `vault 2.0.4-1`; all four binaries
root-owned and world-readable; completion files present in `/etc/bash_completion.d`;
`apt-get update` warns about nothing; `/var/tmp` holds no leftovers.

**Not every tool can report its own version, and that changes the install layout.**
`influx-cli`'s published binaries are built without the version stamp: `influx version` prints
`Influx CLI dev (git: <sha>)` for every release, including the one that matches the published
`.sha256` exactly. There is nothing in the binary's output to compare a pin against, so
`influx-cli.yml` versions the *filesystem* instead — `/usr/local/lib/influx-cli/<version>/influx`
with `/usr/local/bin/influx` symlinked to it — and the guard reads the symlink target with
`stat` (`follow: false`). That also makes the active version visible from `ls -l`, and makes a
stray non-symlink binary at the destination (a leftover from another install method) something
the playbook replaces rather than trusts. Check `<tool> --version` against a *known* version
before designing a guard around it; this is the first tool in either migration where the
output is a constant.

**The unprivileged smoke test needs a working directory, not just a `HOME`.** `gcx` merges a
repository-level `.gcx.yaml` from the *current directory* into its config layering, and the
current directory during a play is wherever ansible happens to run from — a path uid 65534
generally cannot traverse. The first real run of `gcx-cli.yml` failed on
`lstat /home/.../\_multi-user/cloud-cli/.gcx.yaml: permission denied`: a correct install
failing its own verification on the cwd. All four playbooks now `chdir` their smoke tests into
the scratch `HOME`, which costs nothing and removes the whole class. That brings back wave 2's
`chdir` defect — the action validates `chdir` before check mode skips the task — so the scratch
`HOME` create and remove carry `check_mode: false`, exactly as `opentofu.yml` does.

**HashiCorp does publish `resolute`, contrary to what the [note above](#notes-on-the-four-that-need-a-decision)
recorded.** `apt.releases.hashicorp.com/dists/resolute/InRelease` is a real signed Artifactory
index, generated in the same run as `noble` and carrying the same 184 `vault` versions up to
`2.0.4-1`; `plucky` likewise. The A5 codename map is therefore *not* required here — but
`vault-cli.yml` keeps it and maps to `noble` anyway, because `services/vault.yml` configures
this same repository with `noble`, and two entries for one URI under different suites are two
repositories to apt: both get downloaded, and they can resolve to different candidates.
Matching the suite is what A5's "do not fight" rule means. It still holds now that
`services/vault.yml` has been deleted, because the `.list` it wrote survives on every host it
ran on. Worth restating as a rule: **check the vendor's `dists/` yourself; a 404 recorded
during planning may be a suite the vendor has since added.**

**The HashiCorp `.deb` does not enable `vault.service` — so `vault-cli.yml` does not disable
it.** The plan called for the `prometheus-cli.yml` treatment (stop and disable) if the package
enabled its daemon. It does not: `postinst` only runs `daemon-reload`. What it *does* do is
worth knowing for a "client-only" install — `preinst` creates a `vault` system user, and
`postinst` generates a self-signed cert under `/opt/vault/tls`, creates `/opt/vault/data`,
ships `vault.service`, and applies `setcap cap_ipc_lock=+ep` to the binary. That scaffolding is
inert until something enables the unit, and where the unit *is* enabled something outside this
playbook is serving Vault on the host; disabling it there would be a CLI installer taking down
a server it did not start. Task 19 reports the unit state instead of changing it.

Two consequences of `vault` being one package for both client and server, observed on
`localhost`, which already ran `services/vault.yml`:

- Upgrading the pin upgrades the server's binary too, but **the running process keeps executing
  the old code**: after the run `dpkg-query` reported `2.0.4-1` while the (sealed) server still
  reported `Version 2.0.0` on its status endpoint. The new binary takes effect at the next
  `vault.service` restart, which for file storage means unsealing again.
- `/etc/vault.d/vault.hcl` is a dpkg conffile and `services/vault.yml` rewrites it. The upgrade
  kept the modified file, because ansible's `apt` module passes `force-confold`.

**The Homebrew PATH follow-up is now a task, not a note.** Each wave-3 playbook runs
`env -i ... bash -lc 'command -v <tool>'` as uid 65534 and asserts the system-wide path. `env -i`
is the point: PATH then comes purely from `/etc/profile` and, through it, `/etc/bash.bashrc`,
which is where a system-wide `brew shellenv` would land. All four pass on `localhost` — but
that is weaker evidence than it looks, because this host's `brew shellenv` line is in the
user's own `~/.bashrc` (line 131), which no system-wide check can see. `jira` is the case that
proves the limit: `/home/linuxbrew/.linuxbrew/bin/jira` still exists here and still wins for
that one account's interactive shells. **Per-user `~/.bashrc` remains a manual check**, and
the playbooks say so in their summaries.

**A5's fingerprint-versus-bytes rule decided `vault-cli` immediately.** HashiCorp's packaging
key `798AEC654E5C15428C8E42EEAA16FCBCA621E701` expires **2028-01-09**, so it is fetched each
run and only its fingerprint is asserted — the `github-cli` form, not the `azure-cli` one. It
is byte-identical to the copy `services/vault.yml` already installed at
`/etc/apt/keyrings/hashicorp-archive-keyring.asc`; the new `.sources` uses the module's own
`/etc/apt/keyrings/hashicorp.asc`, and the superseded `.list` is removed, so `apt-get update`
reads the repository once. At the time of the run, re-running `services/vault.yml` would have
recreated that `.list` and the duplicate-target warning with it; that playbook has since been
deleted, so the removal task is now plain cleanup of a predecessor's leavings, exactly like
`github-cli.yml`'s and `azure-cli.yml`'s.

**Postscript (2026-08-10): `services/vault.yml` was deleted, and the local Vault server with
it.** The server was stopped and disabled and its storage removed without a backup. Two
observations above are historical rather than current as a result: the local host no longer
runs a Vault server, and there is no server playbook in the repo for `vault-cli.yml` to
coexist with. What does not change is `vault-cli.yml` itself — the `noble` pin and the `.list`
removal both stay, because the file the deleted playbook wrote survives on every host it ran
on. See the [outcome note on #11](#notes-on-the-four-that-need-a-decision). It is also the
cleanest confirmation of the client/server split this playbook was built around: with the
server gone, `vault-cli.yml` re-runs `failed=0` and its summary flips from
`vault.service is enabled` to `disabled`, which is what a client-only host should look like.

Smaller things, recorded because the next playbook will meet them:

- **`influx-cli`'s `.sha256` is one file per asset**, not a shared `checksums.txt`, and its
  entry is `<hash>  /root/project/packages/<file>` — InfluxData's build path, baked in. The
  match pattern allows an optional directory prefix; anchoring on the bare filename finds
  nothing. The asset is still named `influxdb2-client-*` despite the v2.8.0 rename
  announcement: `influxdb2-cli-2.8.0-linux-amd64.tar.gz` is a 404.
- **Asset arch strings differ per project even within one wave.** `jira-cli` publishes
  `linux_x86_64`/`linux_arm64`, `gcx` and `influx-cli` publish `amd64`/`arm64`. Each playbook
  carries its own map; copying one into another 404s on every host.
- **Tarball layouts differ too**: `jira` nests its binary at `jira_<v>_linux_<arch>/bin/jira`,
  `gcx` puts it at the archive root beside a README, `influx` uses a `./`-prefixed flat layout.
  All three unpack into the staging directory and install the one file explicitly, rather than
  extracting into `/usr/local/bin`.
- **Completions are generated, not shipped.** `jira`, `gcx` and `influx` each emit a script
  from a subcommand; all three are written to `/etc/bash_completion.d/<tool>`, which needs no
  `/etc/profile.d` bootstrap. `vault` is different again — it completes through the binary, so
  the file holds the single line `complete -C /usr/bin/vault vault` that
  `vault -autocomplete-install` would otherwise have appended to one account's `~/.bashrc`.
  `bash-completion` is now a prerequisite in all four: without its loader,
  `/etc/bash_completion.d` is inert.
- **`gcx` does not recreate its scratch `HOME` after removal**, unlike `az`. Its telemetry
  (`GCX_TELEMETRY`) writes `~/.local/state/gcx/device-id` synchronously, so the directory stays
  gone. Verified rather than assumed, which is the point of the `az` finding.

## Upstream survey (2026-08-06)

Checked while writing this plan, to confirm each target mechanism exists. **Every version here
must be re-checked at write time, and every apt candidate re-checked against the target host**
— these came from this workstation, which already has several vendor repositories configured
and is therefore not a clean read of what `ws01`/`ws02` see.

| Tool | Finding |
| --- | --- |
| `jira-cli` | `v1.7.0`, GitHub, `jira_1.7.0_linux_x86_64.tar.gz` + plain `checksums.txt`. Asset arch strings are `x86_64`/`arm64`. |
| `gcx` | `v1.0.0`, GitHub, `gcx_1.0.0_linux_amd64.tar.gz` + `gcx_1.0.0_checksums.txt`. |
| `influx-cli` | `v2.8.0`, **no GitHub assets**; `dl.influxdata.com/influxdb/releases/influxdb2-client-2.8.0-linux-amd64.tar.gz` (200 OK) with a path-prefixed `.sha256`. |
| `vault` | HashiCorp repo (`noble` suite) candidate `2.0.4-1`. |
| `glab` | Upstream `v1.112.0` with `checksums.txt`; Ubuntu `resolute/universe` has `1.53.0-1build1` — far too stale for apt. |
| `gh` | Upstream `v2.97.0` via `cli.github.com`; no Ubuntu archive candidate. Vendor repo stays. |
| `awscli` | Ubuntu `resolute/universe` candidate `2.31.35-1`, genuinely v2. See [#7's note](#notes-on-the-four-that-need-a-decision). |
| `promtool` / `prometheus-alertmanager` | Ubuntu `resolute/universe`, `2.53.5+ds1-3` / `0.28.1+ds-3`. apt stays. |
| `az extension add --system` | Confirmed present; system dir overridable via `AZURE_EXTENSION_SYS_DIR`. `azure-devops` max compatible version `1.0.6`. |
| `deb822_repository` | `version_added: 2.15`, so it clears the 2.16 floor and works on both control nodes. A5 is implementable. Requires `python3-debian` on the target and does not update the apt cache itself. |

## Known follow-ups

- **`/etc/profile.d` bootstrap** — already solved by `_multi-user/tools/modern-cli-tools.yml`
  (which patches `/etc/bash.bashrc`), but it becomes a hard dependency again for any tool here
  that ships shell completions (`gh`, `glab`, `tofu`). Settled for wave 3 by taking the second
  route: `jira`, `gcx`, `influx` and `vault` install completions to `/etc/bash_completion.d`,
  which needs no bootstrap — only the `bash-completion` package, now a prerequisite in each.
  `az` is off this list: its apt package ships `/etc/bash_completion.d/azure-cli` itself.
- **`PATH` precedence on hosts that already have Homebrew** — carried over from MIGRATION.md.
  Wave 3 turned the system-wide half into a playbook task (`command -v` under
  `env -i ... bash -lc` as uid 65534, in all four de-brew playbooks). What remains is the
  per-user half, which no playbook can see: a `brew shellenv` line in an individual account's
  `~/.bashrc` still shadows the system-wide binary for that account's interactive shells, and
  `/home/linuxbrew/.linuxbrew/bin/jira` is a live instance of exactly that on this workstation.
  Uninstalling the four brew formulae is a per-host cleanup this migration documents but does
  not perform.
- **`cloud-cli/env-tmpl.sh` successor** — see [A1](#policy-amendments) and the note under the
  identity-state table. Blocks wave 4.
- **Repo-wide vendor-repo ownership** — several directories add apt repositories
  independently, with no shared convention for keyring paths or `sources.list.d` filenames.
  A5 makes the migrated playbooks internally consistent; making them consistent with
  `core/`, `container/` and `gui-tools/` is a separate cleanup that this migration should
  document but not attempt. One instance is closed rather than solved: `services/vault.yml`
  was the HashiCorp case, and it was deleted (see #11's outcome note), so `vault-cli.yml`
  now owns that repository alone.
- **Bare `ansible_architecture` is deprecated.** ansible-core 2.20 warns on every run that
  reads it (`Use ansible_facts["fact_name"] (no ansible_ prefix) instead`), and every playbook
  in `_multi-user/` maps it onto upstream asset names. Currently a warning, not an error.
  `ansible_facts['architecture']` works on 2.16 as well, so this is a safe repo-wide change
  whenever it is worth doing — it is not specific to `cloud-cli/` and should be done in one
  pass across `tools/` and `cloud-cli/` together, not tool by tool. New playbooks are written
  with the non-deprecated spelling from the start rather than adding to the debt, so all
  seven migrated `cloud-cli/` playbooks except `aws-cli.yml` are already done and that pass
  has six fewer files to touch.
