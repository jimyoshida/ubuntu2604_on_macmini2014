# Multi-User Workstation Cloud CLI Playbook Migration

Policy and procedure for migrating the cloud/service CLI playbooks from `cloud-cli/` to
`_multi-user/cloud-cli/`.

**Status: in progress.** 1 of 13 source playbooks migrated, written but not yet run against a
host. See [Migration status](#migration-status).

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
are already configured by playbooks outside this directory (`services/vault.yml` adds the
HashiCorp repo; `core/` and `container/` add others). Every migrated playbook must therefore:

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
| `jira` | `~/.config/.jira/.config.yml` | `JIRA_URL`, `JIRA_LOGIN` | `JIRA_API_TOKEN` |
| `gcx` | `~/.config/gcx/` | `GRAFANA_SERVER` | `GRAFANA_TOKEN` |
| `influx` | `~/.influxdbv2/configs` | `INFLUX_HOST`, `INFLUX_ORG` | `INFLUX_TOKEN` |
| `vault` | `~/.vault-token` | `VAULT_ADDR` | `VAULT_TOKEN` |
| `jenkins-cli` | none | `JENKINS_URL` | `JENKINS_USER_ID`, `JENKINS_API_TOKEN` |
| `az devops` | `~/.azure/config` defaults | `AZURE_DEVOPS_ORG`, `AZURE_DEVOPS_PROJECT` | `AZURE_DEVOPS_EXT_PAT` |

`cloud-cli/env-tmpl.sh` mixes all three columns into one file. Its successor should ship as two
pieces: the shared, non-secret half applied by the playbooks per A1, and a per-user
`~/.config/cloud-cli/env.sh` template (mode `0600`, sourced by the user, gitignored) for the
rest. Decide this before migrating `jenkins-cli.yml`, the first playbook that needs it.

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

**`vault-cli.yml` (#11) — collides with `services/vault.yml`.** Both would install the same
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
2. **Vendor-repo and apt playbooks — #1–#7.** Already system-wide, so this is correctness
   work: A5 cleanup, pins, version-aware guards, smoke tests. Establishes the house style for
   the wave that follows.
3. **De-brew — #8–#11.** The reach work. Each is an independent tool with an independent
   version pin.
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
| `github-cli.yml` | vendor apt repo | vendor apt repo, A5 cleanup | TBD | Planned |
| `opentofu.yml` | vendor apt repo | vendor apt repo, A5 cleanup | TBD | Planned |
| `prometheus-cli.yml` | apt | apt, pinned | TBD | Planned |
| `azure-cli.yml` | vendor apt repo | vendor apt repo, A5 cleanup | TBD | Planned |
| `gcloud-cli.yml` | vendor apt repo | vendor apt repo, A5 cleanup | TBD | Planned |
| `gitlab-cli.yml` | floating latest `.deb` | pinned `.deb` + checksum | TBD | Planned |
| `aws-cli.yml` | vendor zip installer | same installer, pinned + signature-verified | 2.36.17 | Written, not yet run |
| `jira-cli.yml` | brew + tap | release tarball → `/usr/local/bin` | TBD | Planned |
| `gcx-cli.yml` | brew + tap | release tarball → `/usr/local/bin` | TBD | Planned |
| `influx-cli.yml` | brew | `dl.influxdata.com` tarball → `/usr/local/bin` | TBD | Planned |
| `vault-cli.yml` | brew + tap | HashiCorp apt repo (see note) | TBD | Planned |
| `jenkins-cli.yml` | system-wide + `$JENKINS_URL` | unchanged shape; URL from a play var | n/a | Planned |
| `azure-devops-cli.yml` | apt `az` + per-user extension | apt `az` + `az extension add --system` | TBD | Planned |

Versions are deliberately left `TBD`: MIGRATION.md's step 3 requires checking upstream at the
time each playbook is written, and the [upstream survey](#upstream-survey-2026-08-06) below
will be stale by then.

`aws-cli.yml` was taken first, ahead of its position in wave 2. Nothing depends on it and it
depends on none of wave 1's three decisions — it sets no environment variable, shares no vendor
apt repository, and configures no identity — so the ordering above is unaffected.

### Verification status

Rows marked "Written, not yet run" have been YAML-validated, syntax-checked, and reviewed
against the policy, but **not executed against a target host** — `_multi-user/inventory.ini`
is gitignored and absent from this checkout. Treat them as unverified until someone runs
`ansible-playbook cloud-cli/<tool>.yml -e host=<host>` and updates the table.

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
  that ships shell completions (`jira`, `gh`, `glab`, `tofu`, `az`). Order those after it, or
  install completions to `/etc/bash_completion.d` instead, which needs no bootstrap.
- **`PATH` precedence on hosts that already have Homebrew** — carried over from MIGRATION.md
  and now more acute: four of these tools currently live in `/home/linuxbrew/.linuxbrew/bin`,
  and if `brew shellenv` still wins, users keep silently running the brew copy of `vault` or
  `influx` after migration. Verify with `command -v` inside the unprivileged smoke test, not
  just that the binary works.
- **`cloud-cli/env-tmpl.sh` successor** — see [A1](#policy-amendments) and the note under the
  identity-state table. Blocks wave 4.
- **Repo-wide vendor-repo ownership** — `services/vault.yml` is one instance of a broader
  question: several directories add apt repositories independently, with no shared convention
  for keyring paths or `sources.list.d` filenames. A5 makes the migrated playbooks internally
  consistent; making them consistent with `core/`, `container/`, and `services/` is a separate
  cleanup that this migration should document but not attempt.
