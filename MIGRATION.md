# Multi-User Workstation Tool Playbook Migration

Policy and procedure for migrating the developer tool installation playbooks from
`tool/` to `_multi-user/tools/`.

**Status: complete.** 10 of 10 source playbooks migrated, as 11 target playbooks (`yq` split
out of `modern-cli-tools.yml`). See [Migration status](#migration-status).

## Background

`tool/` provisions a **single-user** Ubuntu development workstation. On a
**shared** workstation those playbooks install tooling that only the account which ran them
can use. Three distinct causes:

1. **Homebrew ownership.** `/home/linuxbrew/.linuxbrew` is owned by whoever ran
   `core/homebrew.yml` (in practice `ubuntu`). Other users can execute the binaries but
   cannot `brew install`, `brew upgrade`, or `brew update`. Homebrew upstream does not
   support multi-user installs and refuses `sudo brew`; making the tree group-writable
   works only until the next upgrade resets permissions.
   Affects: `bats`, `shellcheck`, `trivy`, `hadolint`, `grype-syft`, `modern-cli-tools`, `yq`.
2. **Per-user shell profiles.** `blockinfile` against `~/.bashrc` writes to exactly one home
   directory. Accounts created later get nothing.
   Affects: `modern-cli-tools` (fzf key bindings) and `core/homebrew.yml` (`brew shellenv`).
3. **Per-user install prefixes.** pipx defaults to `~/.local/bin`.
   Affects: `junit2html`.

Every affected playbook binds work to `lookup('env', 'USER')`, which encodes "the one person
running this".

## Scope

| | |
| --- | --- |
| Source | `tool/*.yml` (10 playbooks) |
| Target | `_multi-user/tools/*.yml` |
| Applies to | New multi-user workstation builds |

**On the target naming.** The leading underscore in `_multi-user/` and the plural `tools/`
are deliberate, not drift. The underscore sorts the tree apart from the live playbook
directories (`core/`, `tool/`, `container/`, ...) and marks it as staging; the plural avoids
a collision with the `tool/` it will eventually replace. Both are expected to go away when
`tool/` is retired — until then, leave them as they are.

**Out of scope:**

- `{core,cloud-cli,container,ai-agent}/` — a separate question. Much of it
  is genuinely per-identity (credentials, agent configs, language version managers) and
  should stay per-user, but parameterised by an explicit user list instead of `$USER`.
- `tool/*` itself is left in place until the new workstation build is
  proven.

## Prerequisites

Unlike the rest of this repo, these playbooks run **against a remote host**. Everything under
`core/`, `tool/`, `container/`, `cloud-cli/`, `ai-agent/`, and `media/` is `hosts: localhost`
with `connection: local` — run on the machine being provisioned, with passwordless sudo from
`setup-passwordless-sudo.sh`. The multi-user playbooks are a push model instead:
`hosts: "{{ host }}"`, `remote_user: ubuntu`, `become: true`.

That needs an inventory, and a config pointing at it. Both live in `_multi-user/` next to
`tools/`, which is why every command in this document starts with `cd _multi-user` — Ansible
reads `ansible.cfg` from the working directory.

`_multi-user/ansible.cfg` is committed and needs no edits. The inventory is not committed,
since it holds real hostnames and addresses; copy the example and fill it in:

```bash
cd _multi-user
cp inventory.ini.example inventory.ini
```

`inventory.ini.example` defines a `workstations` group, so `-e host=workstations` provisions
every workstation and `-e host=ws01` provisions one. `inventory.ini` itself is gitignored.

And on each target host:

- **An `ubuntu` account** — the `remote_user` in the skeleton — reachable over SSH with key
  authentication from wherever the playbooks are run. If the account is named differently,
  override it per run with `-e ansible_user=<name>` rather than editing each playbook.
- **Passwordless sudo for that account.** `setup-passwordless-sudo.sh` does this, but it
  configures whoever invokes it, so it has to be run *on the target* as that account. Without
  it, every run needs `-K`.
- **Python 3**, which is present on stock Ubuntu server images.

Confirm reachability before the first migration run:

```bash
cd _multi-user
ansible -m ping <host>
```

## Policy

The governing rule:

> Shared tooling goes to root-owned system paths. Shell configuration goes to `/etc`
> drop-ins. Only things that are genuinely per-identity stay in `$HOME`, and those take an
> explicit user list rather than reading `$USER`.

Concretely, every playbook under `_multi-user/tools/` must satisfy:

1. **Root-owned system paths only.** Binaries to `/usr/local/bin`, or apt. Shared libraries
   to `/usr/lib/<tool>` or `/usr/local/lib/<tool>`. Build/source trees to `/usr/local/src`.
2. **No Homebrew.** Every tool in scope has a distro package, a vendor apt repository, an
   upstream release binary, or an upstream `install.sh`.
3. **No writes to any `$HOME`.** Environment variables go to `/etc/environment` (applied to
   login and SSH sessions via PAM). Interactive-only settings — key bindings, completions,
   aliases — go to `/etc/profile.d/<tool>.sh`, which requires `/etc/bash.bashrc` to source
   it so that non-login interactive shells pick it up (see
   [Known follow-ups](#known-follow-ups)). `/etc/skel/` is not a substitute: it only affects
   accounts created afterwards.
4. **Explicit world-readable modes.** Set `mode: 'u=rwX,go=rX'` on install trees rather than
   relying on the umask of whoever ran the playbook. Set `owner: root`, `group: root`
   explicitly on installed files.
5. **Pinned versions in the play's `vars`,** overridable with `-e`.
6. **Version-aware idempotency.** Guard installs on the *installed version*, never on
   `stat.exists`. A file-existence guard makes version bumps silently no-op.
7. **Integrity verification** for anything downloaded outside apt. Prefer resolving the hash
   from the release's published checksum file at run time over hardcoding it, so that
   overriding the version stays a one-flag change.
8. **Architecture from facts.** Map `ansible_architecture` to the upstream asset name and
   fail loudly on an unmapped value. Do not assume amd64.
9. **Unprivileged verification.** End with a task that exercises the tool as an arbitrary
   uid via `setpriv --reuid=65534 --regid=65534 --clear-groups`, **not** as the connecting
   user. This is the regression guard: a single-user regression must fail the run rather
   than pass because `ubuntu` happens to have the right environment. Where the tool has
   configuration discovery (search paths, library paths), leave the relevant variable unset
   in that task so the zero-configuration path is what gets proven.
10. **Self-contained playbooks, not roles.** One playbook per tool, no dependency on
    `roles/`, so a new workstation can be built up tool by tool and the existing roles stay
    untouched.

## Playbook skeleton

```yaml
---
# <one-paragraph statement of what lands where, and why that is multi-user safe>
#
# Usage:
#   ansible-playbook tools/<tool>.yml -e host=<inventory host or group>

- name: Install <tool> system-wide
  hosts: "{{ host }}"
  become_user: root
  become_method: sudo
  become: true
  remote_user: ubuntu
  gather_facts: true

  vars:
    <tool>_version: "x.y.z"
    <tool>_verify_uid: 65534    # nobody
    <tool>_verify_gid: 65534    # nogroup

  tasks:
    - name: 1. Install prerequisites
    - name: 2. Check the currently installed <tool> version
    - name: 3. Decide whether <tool> needs installing
    - name: 4. ... install ...
    - name: N-2. Verify the installed <tool> version
    - name: N-1. <exercise the tool> as an unprivileged user
    - name: N. Display installation summary
```

Conventions: `hosts: "{{ host }}"` driven by an extra var, the `become`/`remote_user: ubuntu` header block, and numbered task names.

## Install mechanism decision order

Choose the first that applies:

| Order | Mechanism | Use when | Example |
| --- | --- | --- | --- |
| 1 | Ubuntu apt package | the distro package is current enough and named as expected | `shellcheck` |
| 2 | Vendor apt repository | the vendor publishes one and the distro package lags | `trivy` |
| 3 | Upstream release binary → `/usr/local/bin` | single static binary | `gomplate`, `hadolint`, `kube-score` |
| 4 | Upstream git tag + `install.sh` | the tool ships an installer and helper libraries | `bats` |
| 5 | pipx as root, `PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin` | Python application | `junit2html` |
| 6 | `npm install -g` with `become` | Node application; lands in npm's global prefix | `markdownlint` |

Two apt gotchas to check before choosing option 1:

- **`yq`** — the apt package is the Python jq-wrapper, **not** mikefarah's Go `yq` that
  Homebrew installs. Scripts expecting the Go one need the release binary.
- **`bat`** — apt installs the binary as `batcat` (name clash with `bacula-console`). Add a
  `/usr/local/bin/bat` symlink if anything calls `bat`.

## Procedure

For each playbook:

1. **Read the source playbook** in `tool/` and identify which of the three
   background causes apply. Some playbooks (`gomplate`, `kube-score`) already
   install system-wide; for those the migration is correctness work, not reach work.
2. **Choose the target mechanism** from the decision order above.
3. **Check upstream for the current version** rather than carrying the old pin forward
   blindly:
   ```bash
   git ls-remote --tags --refs https://github.com/<org>/<repo>.git \
     | sed 's#.*refs/tags/##' | sort -V | tail -5
   curl -s https://api.github.com/repos/<org>/<repo>/releases/latest
   ```
4. **Check in-repo consumers before changing a version default**, especially across a major
   version:
   ```bash
   grep -rn "<tool>" --include=* -l . | grep -v node_modules | grep -v '\.git/'
   ```
   If a consumer exists, keep the old pin. If none exists, take the current release and
   state the change explicitly in the README and the commit message.
5. **Confirm the download details** — asset naming per architecture, and whether a checksum
   file is published and how its entries are formatted (some prefix paths, e.g. `bin/`).
   Verify any anchored match pattern is unambiguous against the full checksum file.
6. **Write the playbook** to the skeleton, satisfying all ten policy points.
7. **Validate the YAML** (no Ansible needed on a Windows checkout):
   ```bash
   python -c "import io,yaml; d=yaml.safe_load(io.open('tools/<tool>.yml',encoding='utf-8')); print(len(d[0]['tasks']),'tasks')"
   ```
8. **Add a section to `_multi-user/tools/README.md`** covering install paths, what
   changed versus the source playbook, version override syntax, and any migration note for
   downstream consumers.
9. **Update the status table below.**
10. **Run it against a target host.** Syntax check first, then a real run:
    ```bash
    cd _multi-user
    ansible-playbook tools/<tool>.yml -e host=<host> --syntax-check
    ansible-playbook tools/<tool>.yml -e host=<host>
    ```
    Note that `--check` will skip or fail the install/verify/smoke-test tasks on a host where
    the tool is not yet present; it is not a meaningful dry run for these playbooks.

## Migration status

| Source playbook | Old mechanism | Target mechanism | Pinned | Status |
| --- | --- | --- | --- | --- |
| `bats.yml` | brew + tap | git tags + `install.sh`; libs to `/usr/lib/bats` | core 1.14.0, support 0.3.0, assert 2.2.4 | Verified (workstations, localhost) |
| `gomplate.yml` | release binary | release binary + checksum + arch from facts | 5.2.0 (was 4.3.0) | Verified (workstations) |
| `shellcheck.yml` | brew | apt `shellcheck` | 0.11.0-2 (dpkg version, Ubuntu 26.04) | Verified (workstations, localhost) |
| `trivy.yml` | brew | Aqua vendor apt repo | 0.73.0 | Verified (workstations, localhost) |
| `hadolint.yml` | brew | release binary | 2.15.1 | Verified (workstations, localhost) |
| `grype-syft.yml` | brew | upstream `install.sh -b /usr/local/bin` | grype 0.116.1, syft 1.50.0 | Verified (ws01, ws02, localhost) |
| `modern-cli-tools.yml` | brew (16 tools) | apt for 14 tools; llhttp dropped (apt eza needs no manual libllhttp symlink); yq split out to `yq.yml` | see README | Verified (workstations, localhost) |
| `modern-cli-tools.yml` (`yq`) | brew | release binary via `yq.yml` (apt `yq` is the unrelated Python wrapper) | 4.53.3 | Verified (workstations, localhost) |
| `junit2html.yml` | pipx → `~/.local/bin` | pipx as root → `/usr/local/bin` | 31.1.4 | Verified (ws01, ws02) |
| `markdownlint.yml` | `npm install -g` | unchanged mechanism; pinned version, version-aware guard, npm prefix from facts not assumed | 0.49.1 | Verified (ws01, ws02) |
| `kube-score.yml` | release binary | unchanged mechanism; add checksum, arch, version-aware guard | 1.20.0 | Verified (ws01, ws02) |

`vault.yml` and `vscode.yml` dropped out of this table: both moved out of `tool/` (to
`services/` and `gui-tools/` respectively) before their multi-user migration started, so
they're no longer in scope for `tool/*.yml` → `_multi-user/tools/*.yml`. Whether they need
a multi-user treatment is a question for wherever they live now, not this document.

All ten remaining `tool/*.yml` playbooks are migrated and verified against `ws01`/`ws02`
(eleven target playbooks, since `yq` is split out of `modern-cli-tools.yml` into its own
`yq.yml`).

One tool present in a real `/home/linuxbrew` prefix is deliberately **not** in this table:
`shellspec`. It had no `tool/*.yml` playbook and so was never in scope — it was installed by
hand with `brew`, which is exactly the class of install this migration cannot see. It was
dropped rather than migrated on 2026-08-11. The general point survives the specific case:
this table covers what the repo installed, not everything a given prefix happens to contain.

## Known follow-ups

These are required for a complete migration but are not part of any single tool playbook:

- **`/etc/profile.d` bootstrap.** `/etc/profile.d/*.sh` is only sourced by login shells. An
  SSH session that starts a non-login interactive bash reads `/etc/bash.bashrc`. A shared
  base playbook must add:
  ```yaml
  - name: Ensure interactive non-login shells read /etc/profile.d
    ansible.builtin.blockinfile:
      path: /etc/bash.bashrc
      marker: "# {mark} ANSIBLE MANAGED BLOCK: profile.d for interactive shells"
      block: |
        for f in /etc/profile.d/*.sh; do [ -r "$f" ] && . "$f"; done
  ```
  Needed before `modern-cli-tools` (fzf key bindings) could be migrated properly; already
  applied there (see `modern-cli-tools.yml`'s `/etc/bash.bashrc` task).
- **`PATH` precedence on hosts that already have Homebrew.** If `/home/linuxbrew` is left in
  place after migrating, `brew shellenv` prepends its `bin` to `PATH`, so users keep
  silently getting the stale brew copies instead of `/usr/local/bin`. Decide per host
  whether to remove the brew tree or to ensure `/usr/local/bin` wins. On `localhost` this was
  settled the first way on 2026-08-11: the tree was removed. See the follow-up entry in
  [MIGRATION2.md](MIGRATION2.md#known-follow-ups) for what that run turned up.

## Verification status

Playbooks marked "Written, not yet run" have been YAML-validated and reviewed against the
policy but **not executed** — that requires an Ubuntu target host. Treat those rows as
unverified until someone runs them and updates this table. Rows marked "Verified" have been
run against the listed host(s) with `ansible-playbook tools/<tool>.yml -e host=<host>` and
completed with `failed=0`.

`grype-syft.yml` needed a fix discovered only at run time: on `ws01`/`ws02`, `/tmp` is a
size-capped tmpfs (~1.65GiB) too small for grype's vulnerability database, which failed with
`SQLITE_FULL` when downloaded there during the unprivileged-verification step. The playbook
now stages that step under `/var/tmp` (disk-backed) instead. Worth checking for on any tool
whose verification step writes non-trivial amounts of data under `HOME=/tmp`. `trivy.yml`
applied the same `/var/tmp` staging from the start, since its vulnerability database is a
similar size (~100MiB).

`shellcheck.yml` needed a version fix discovered only at run time: `ws01`/`ws02` run Ubuntu
26.04 ("resolute"), not 24.04 ("noble") as assumed when picking the initial pin from a local
apt cache. apt's `shellcheck` candidate differs by release (`0.11.0-2` vs `0.9.0-1`), and the
task 3 install fails outright — "no available installation candidate" — when the pin doesn't
match what the target's apt sources actually carry. Worth checking the target's actual
`/etc/os-release` before trusting an apt-based version pin, not just a local machine's.

`modern-cli-tools.yml`'s planned mechanism was wrong on two counts, both only visible by
checking the actual target: Ubuntu 26.04's apt already carries `gum` and `glow` directly
(0.17.0-1, 2.1.1-1), so the Charm vendor apt repo this row originally called for turned out
to be unnecessary — apt alone covers all 14 tools. `llhttp` (a manual symlink hack the source
playbook needed for Homebrew's eza build) is also dropped entirely: apt's `eza` package
declares its own library dependencies, so nothing extra is needed.

`yq` was migrated as part of `modern-cli-tools.yml` but is split into its own `yq.yml`, since
it is not a plain apt install like the other 14: apt's `yq` is confirmed to be the Python
jq-wrapper, not mikefarah's Go yq, so it installs from a release binary instead. That
release's own checksums file uses a bespoke multi-algorithm rhash table
(`checksums_hashes_order` / `extract-checksum.sh`) rather than the usual `hash  filename`
format the other release-binary playbooks parse; the playbook uses GitHub's own computed
per-asset SHA-256 `digest` (from the releases API) instead, which is simpler and equally
authoritative.

`junit2html.yml` needed a version-source change discovered only when checking upstream
directly, not just its GitHub tags: `inorton/junit2html` moved off GitHub to
`gitlab.com/inorton/junit2html` after tag `v31.0.2`, so later PyPI releases (`31.1.4` and
newer) have no corresponding GitHub tag at all. The pin is taken from PyPI's release
history instead, and no separate checksum step was added — `pip`/`pipx` already verify the
downloaded package against the hash PyPI publishes in its index as part of every install,
so a manual checksum task would be redundant. Also, junit2html has no `--version` flag;
both the idempotency check and the post-install verification instead parse
`pipx list --short`, which prints `junit2html <version>` once installed.

`kube-score.yml` needed no version bump — the source playbook's pin (`1.20.0`) is still
upstream's latest tag — so this migration was pure hardening: checksum verification from
the release's `checksums.txt`, architecture from `ansible_architecture` instead of an
assumed `amd64`, and comparing the installed version instead of the old `stat.exists`
guard. Its unprivileged verification step scores a Deployment manifest deliberately
written with a floating `:latest` image tag, no resource limits, and no security context;
kube-score exits non-zero when it finds `CRITICAL` issues, which is the expected outcome
of that check, not a run failure, so the task's `failed_when` looks for the specific
issue text in the output rather than a zero exit code.

Also found while migrating `modern-cli-tools.yml`, but predating it: `bats.yml` and
`grype-syft.yml`'s installation-summary tasks built a per-item newline with a bare `\n`
inside a Jinja `{% if %}...{% endif %}` block. Ansible's Jinja environment has
`trim_blocks` enabled, which silently strips a newline immediately following a block tag,
so that `\n` was never actually emitted — the summary printed all items joined on one line
instead of one per line. Wrapping it as an expression, `{{ '\n' }}`, is not subject to
`trim_blocks` and fixes it. Fixed in both existing playbooks and written correctly from the
start in `modern-cli-tools.yml`; worth using `{{ '\n' }}` rather than a bare `\n` in any
future summary task that loops.

`markdownlint.yml`'s planned mechanism ("lands in `/usr/lib/node_modules`") was wrong in a
way only visible by checking both actual targets, not just one: `ws01`'s Node.js comes from
the NodeSource repository, which sets npm's global prefix to `/usr`, while `ws02`'s comes
from Ubuntu's own `nodejs` apt package, which defaults it to `/usr/local` instead. Both are
root-owned system paths, but a playbook that hardcoded either would silently install to the
wrong tree — or the right tree with the wrong bin dir — on the other host. The playbook
reads `npm config get prefix` at run time instead. Its unprivileged verification step also
needed a fix discovered only at run time: markdownlint writes its lint findings to
**stderr**, not stdout, so a `failed_when` written against `.stdout` never matched and the
task failed even though the tool worked correctly.
