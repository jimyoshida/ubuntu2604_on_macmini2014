# Multi-User Workstation Core Playbook Migration

Policy and procedure for migrating the last three playbooks — `core/core-tools.yml`,
`core/mise.yml`, `core/nodejs.yml` — from `core/` to `_multi-user/core/`.

**Status: complete.** All three playbooks are migrated, verified against `localhost`, and
retired — the originals and `core/README.md` were deleted on 2026-08-16 and `core/` is gone with
them, the same as `tool/`, `cloud-cli/` and `container/` before it. `_multi-user/core/` now holds
`core-tools.yml`, `nodejs.yml` and `mise.yml`, each run to `failed=0` against `localhost`, re-run
idempotently, and checked clean under `--check` — see [Migration status](#migration-status).
**Read [what the retirement gate did and did not cover](#known-follow-ups) before relying on the
deletion**: it is the same `localhost`-only, ansible-core 2.20-only evidence `container/` was
retired on, and the 24.04-control-node-over-SSH run this plan called for was never performed.

This document is the fourth in the series and the last: `core/` was the whole of what remained
of the original single-user tree (`tool/`, `cloud-cli/` and `container/` were already gone — see
the three documents above), and retiring it retires the entire legacy tree — nothing named
`core/`, `tool/`, `cloud-cli/`, `container/`, `services/` or `gui-tools/` remains anywhere in the
repo. Everything in the three documents above still applies: the
[prerequisites](MIGRATION.md#prerequisites), the ten [policy](MIGRATION.md#policy) points, the
[playbook skeleton](MIGRATION.md#playbook-skeleton), the [install mechanism decision
order](MIGRATION.md#install-mechanism-decision-order), MIGRATION2's five
[amendments](MIGRATION2.md#policy-amendments) A1–A5, and MIGRATION3's five
[amendments](MIGRATION3.md#policy-amendments) B1–B5. This document records only what is
*different* about `core/`, plus the per-tool plan — and, unlike the three before it, it needed
**no new lettered amendments**. See [Policy](#policy).

## Background

`core/` used to be the hard case. MIGRATION3.md's scope note called it "a harder problem than
any of the three tool directories: `agent-base.yml` mixed desktop-session setup into hostname,
network and package tasks, which read as per-identity in a way no relocation could fix." That
turned out to be wrong in the useful direction: the desktop half was separable, not structural.
`x11vnc.yml`, `disable-rsyslog.yml` and `samba.yml` were retired outright (out of scope for a box
whose work arrives over SSH, not a multi-user defect to fix), and `agent-base.yml` itself lost
its SSH, Avahi, logind, journald, hostname and IPv6 tasks one cut at a time until only its `apt
install` task was left — renamed `core/core-tools.yml` on 2026-08-14. What is left is three
playbooks, already classified in the root [README](README.md#multi-user-support-status):

| Playbook | Category | Why |
| --- | --- | --- |
| `core/core-tools.yml` | Effectively shared | apt only — nothing lands in a `$HOME` |
| `core/nodejs.yml` | Effectively shared | apt only — nothing lands in a `$HOME` |
| `core/mise.yml` | Mixed | apt install, plus `mise activate` appended to `~/.bashrc` |

None of MIGRATION.md's three original causes, MIGRATION2's two additions, or MIGRATION3's three
apply at anything like the scale they did in the previous three directories:

1. **Homebrew ownership.** Does not apply. `core/homebrew.yml` is retired and nothing left in
   `core/` uses `brew`.
2. **Per-user shell profiles.** Applies to exactly one line: `mise.yml`'s `blockinfile` against
   `~/.bashrc`. Neither `core-tools.yml` nor `nodejs.yml` writes to any `$HOME`.
3. **Per-user install prefixes.** Does not apply. `nodejs.yml`'s two `npm install -g` tasks
   already target npm's global prefix, which on this host is root-owned (`/usr`, from
   NodeSource) — decision-order mechanism 6, the same one `_multi-user/tools/markdownlint.yml`
   already uses.
4. **Install-time `lookup('env', ...)`.** Does not apply. None of the three reads `$USER` or any
   other environment variable at all.
5. **Secrets.** Does not apply. Nothing here has a token or a credential.
6. **Privilege grants / per-user runtime state / hidden security side effects (B1, B2, B5's
   `xhost` question).** Does not apply in the container-playbook sense — nothing here joins a
   group or drives a daemon. `mise.yml` does have a B2-shaped question buried in it; see the
   `$HOME`-on-`--version` finding under [mise.yml](#miseyml-the-a5-form-the-b3-destination-and-a-home-finding)
   below.

So this migration is almost entirely the class MIGRATION2 called "correctness work" rather than
"reach work": two of the three playbooks (`core-tools.yml`, `nodejs.yml`) already install to
root-owned paths and need hardening, not relocation. The third (`mise.yml`) needs one relocation
— the `~/.bashrc` line — that MIGRATION3's B3 already has a direct answer for, because a
playbook already in this repo has done the identical thing: `_multi-user/tools/
modern-cli-tools.yml` puts `eval "$(fzf --bash)"` in `/etc/profile.d/fzf.sh`. `mise activate
bash`'s `eval "$(mise activate bash)"` is the same shape — a PATH/env-rewriting hook, not a
completion and not an alias — so it takes the same destination. See
[mise.yml](#miseyml-the-a5-form-the-b3-destination-and-a-home-finding) below.

The version-discipline gap MIGRATION3 found across `container/` recurs here too, in a smaller
form: `core-tools.yml` pins nothing (plain `state: present` on eighteen packages), `mise.yml`
pins nothing, and `nodejs.yml` pins nothing except by way of running whatever the upstream
`setup_lts.x` script happens to configure that day. Fixing this is most of the actual work below.

## Scope

| | |
| --- | --- |
| Source | `core/*.yml` (3 playbooks) |
| Target | `_multi-user/core/*.yml` |
| Applies to | New multi-user workstation builds |
| Control node | Ubuntu 24.04 (ansible-core **2.16**) **or** Ubuntu 26.04 (ansible-core 2.20) |
| Targets | Ubuntu 26.04 (`localhost`, `ws01`, `ws02`), Python 3.14 |

The 2.16 floor from [MIGRATION2's scope note](MIGRATION2.md#scope) is unchanged: nothing this
plan calls for postdates `deb822_repository` (2.15), already in use across `_multi-user/`.

**On the target naming.** `_multi-user/core/`, singular, matching the source directory — the
same reasoning as `cloud-cli/` and `container/`: the parent distinguishes them, no plural
needed. The directory already exists, empty; nothing has been written into it.

**Out of scope:**

- `core/README.md`'s "chrony" section — not a playbook, and never migrated; it is recoverable
  from git history (`git log --diff-filter=D -- core/README.md`) along with the rest of the file.
- ~~`core/*` itself stays in place until its successors are verified~~, the same way the three
  before it did. ~~Retirement is the last step, not the first.~~ **Retired 2026-08-16.** All
  three originals and the directory's README were deleted once every successor was verified, and
  `core/` no longer exists. What "verified" covers is narrower than the word suggests — see the
  [follow-up](#known-follow-ups) — and the originals are recoverable from git history
  (`git log --diff-filter=D -- core/`).

## Policy

**No new lettered amendments.** Every question `core/` raises already has an answer:

| Question | Answered by |
| --- | --- |
| Pin versions, guard on the installed version not `stat.exists` | MIGRATION.md points 5–6 |
| Architecture from facts, not a hardcoded `amd64` | MIGRATION.md point 8 |
| Vendor apt repository → `deb822_repository`, key form chosen by expiry | MIGRATION2's A5 |
| A shell hook that is not a completion → `/etc/profile.d/<tool>.sh` | MIGRATION3's B3 |
| Per-user state the tool creates for itself → never pre-created by the playbook | MIGRATION3's B2 |
| Unprivileged verification, real work preferred over `--version` alone | MIGRATION2's A4 |

The one place this plan comes closest to needing something new is `nodejs.yml`'s Yarn/pnpm
tasks, and that turns out to be a single-tool finding rather than a cross-cutting policy
question — see the Yarn/pnpm finding under
[nodejs.yml](#nodejsyml-the-version-decision-and-the-yarnpnpm-finding) below.

## Per-tool migration plan

Mechanism numbers refer to MIGRATION.md's [decision
order](MIGRATION.md#install-mechanism-decision-order).

| # | Playbook | Today | Target mechanism | Principal work |
| --- | --- | --- | --- | --- |
| 1 | `core-tools.yml` | apt, unpinned, no guard, no verification | (1) unchanged | pin all 18 packages; version-aware guard; per-package unprivileged smoke test |
| 2 | `nodejs.yml` | `curl \| bash` NodeSource setup script, unpinned; `npm install -g` for Yarn/pnpm behind a `creates:` guard | (2) `deb822_repository` instead of the setup script; (6) unchanged for the npm installs, but see the note | pin the Node major stream and version; A5 cleanup; arch from facts; fix the Yarn/pnpm install — see note; unprivileged smoke test |
| 3 | `mise.yml` | vendor apt repo via `get_url` + `shell: gpg --dearmor` + `apt_repository`, unpinned; `blockinfile` on `~/.bashrc` | (1)-adjacent — apt unchanged, but A5 cleanup on the repo; activation moves per B3 | A5 cleanup (URL key form — expires 2028-01-02); pin version; arch from facts; move activation to `/etc/profile.d/mise.sh`; unprivileged smoke test — see the `$HOME` finding |

### `core-tools.yml`: the plain case, and one open question

Nothing here needs a decision about *mechanism*: apt, root-owned, already correct in outcome.
The only real design question is what "exercise the tool as an unprivileged user" (policy point
9) means for eighteen packages that are not all CLI tools with a `--version` flag —
`modern-cli-tools.yml`'s per-package `binary:` field is the precedent to follow, but this list is
more heterogeneous than that one. A first pass at the mapping, **to be confirmed against the
actual installed binaries at write time** rather than trusted from memory (the same discipline
MIGRATION.md's `shellcheck` finding and MIGRATION3's several found-wrong inferences both argue
for):

| Package | Binary | Expected verify command | Confidence |
| --- | --- | --- | --- |
| `curl` | `curl` | `curl --version` | high |
| `gnupg` | `gpg` | `gpg --version` | high |
| `lsb-release` | `lsb_release` | `lsb_release --version` | high |
| `git` | `git` | `git --version` | high |
| `git-lfs` | `git-lfs` | `git lfs version` | high |
| `git-secret` | `git-secret` | `git secret --version` | medium |
| `jq` | `jq` | `jq --version` | high |
| `make` | `make` | `make --version` | high |
| `vim` | `vim` | `vim --version` | high |
| `unzip` | `unzip` | `unzip -v` | medium |
| `zip` | `zip` | `zip -v` | medium |
| `net-tools` | `netstat` | `netstat --version` | medium |
| `ncat` | `ncat` | `ncat --version` | medium |
| `figlet` | `figlet` | `figlet -v` | medium |
| `dos2unix` | `dos2unix` | `dos2unix -V` | medium |
| `python3-pip` | `pip3` | `python3 -m pip --version` | high |
| `cowsay` | `cowsay` | no version flag — invoke it and assert the output contains the input text | low |
| `aha` | `aha` | no confirmed version flag — likely `aha --help` exit-code only | low |
| `ca-certificates` | none | not a binary — verify `/etc/ssl/certs/ca-certificates.crt` exists, is non-empty, and is world-readable | high |

`ca-certificates` and `cowsay`/`aha` are the reason this needs a table rather than a single
`binary:` field like `modern-cli-tools.yml`'s: one package ships no executable at all, and two
ship one with no way to ask its version. All three still verify **something real** (a file, or
actual output), which fits A4's stated preference for real work over `--version` alone anyway.

Pinning is the more mechanical half: eighteen `apt-cache policy` lookups against the target,
following exactly the `modern-cli-tools.yml` shape — a `vars:` list of `{name, version}`, one
`dpkg-query` loop to see what needs installing, one filtered `apt` install of the ones that
don't already match, one loop to verify afterward.

### `nodejs.yml`: the version decision and the Yarn/pnpm finding

**The Node version is a decision, not a detail — LTS is a moving target and today's playbook
records nothing about which release it picked.** Checked live on this host on 2026-08-14:

```console
$ cat /etc/apt/sources.list.d/nodesource.sources
Types: deb
URIs: https://deb.nodesource.com/node_24.x
Suites: nodistro
...
$ apt-cache policy nodejs
  Installed: 24.15.0-1nodesource1
  Candidate: 24.19.0-1nodesource1
```

Node 24 is the current LTS stream (`setup_lts.x` resolved to it on whatever day this host last
ran the playbook). Recommend pinning `nodejs_version: "24.19.0-1nodesource1"` explicitly and
stating, as `kubectl.yml` did for its stream in MIGRATION3, that **the major stream is part of
the pin**: moving to Node 26 when it becomes the LTS means editing the repository URI
(`node_24.x` → `node_26.x`), not just the version string.

**A5 cleanup replaces the setup script with a declarative repository task**, the same choice
`azure-cli.yml`, `docker.yml`, `github-cli.yml` and every other vendor-repo playbook in
`_multi-user/` already made over running a vendor's own installer. NodeSource's key has **no
expiry** (`gpg --show-keys` against `https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key`
returns an empty expiration field), so per MIGRATION3's fingerprint-versus-bytes rule this is the
`docker.yml`/`azure-cli.yml` form: pin the key bytes inline in `Signed-By`, not the
`github-cli.yml`/`kubectl.yml` fetch-by-URL form. Confirmed both `amd64` and `arm64` `Packages`
indices exist, so `Architectures:` must come from `ansible_architecture`
(mapped to dpkg names) rather than the hardcoded `amd64` neither today's script-based task nor a
naive rewrite would need — the setup script maps this itself; the playbook's own declarative
task has to do the same mapping other A5 playbooks already carry.

**On this host, Yarn and pnpm are not what `nodejs.yml` thinks it installed.** Tasks 6 and 8 run
`npm install -g yarn` / `npm install -g pnpm` guarded by `creates: /usr/bin/yarn` / `creates:
/usr/bin/pnpm`. Checked live:

```console
$ ls -la /usr/bin/pnpm /usr/bin/yarn
/usr/bin/pnpm -> ../lib/node_modules/corepack/dist/pnpm.js
/usr/bin/yarn -> ../lib/node_modules/corepack/dist/yarn.js
```

Both paths are Corepack shims that ship *with the `nodejs` package itself* — NodeSource has
bundled Corepack by default since well before this Node 24 install. Whatever ran on this host
historically, what is at those two paths right now is not an npm-installed package: it is
Corepack's own dispatcher, and the `creates:` guard cannot tell the difference — it only checks
whether the path exists, and apt's `nodejs` postinst is one more thing that can put something
there. That is exactly the failure mode: a guard that cannot distinguish "this repo's pinned
install" from "something else happened to leave a file at this path" is not a guard at all. What
actually happens when an account runs `pnpm --version` for the first time is Corepack downloading
a version of its own choosing on demand:

```console
$ pnpm --version
! Corepack is about to download https://registry.npmjs.org/pnpm/-/pnpm-11.21.0.tgz
11.21.0
```

That is not this repo's pin, it is npm registry's current `pnpm` release at the moment the first
account happens to invoke it — non-deterministic across accounts and across time, and (per
Corepack's default download-per-`$HOME` behavior) a separate download for every account that
triggers it, landing in whatever npm/Corepack cache directory that account's `$HOME` resolves to.
The playbook's own task 7/9 "verify" steps report this borrowed version as if the playbook had
installed it. Two ways out:

- **(a) Recommended.** `corepack disable` first (removes the two shims Corepack manages), then
  the existing `npm install -g yarn@<version> pnpm@<version>` mechanism — decision-order
  mechanism 6, already proven in this repo by `_multi-user/tools/markdownlint.yml` — installs
  real, pinned, root-owned global packages at the same paths. Simplest, and consistent with the
  one npm-global mechanism this repo already trusts.
- (b) Keep Corepack as the install mechanism and pin it explicitly: `corepack prepare
  yarn@<version> pnpm@<version> --activate` as root, with `COREPACK_HOME` pointed at a shared,
  world-readable, root-owned directory (`/etc/environment`, per MIGRATION.md policy point 3 /
  MIGRATION2's A1) instead of the per-account default. More moving parts — a shared cache
  directory to create and own, an environment variable to assert every account actually reads —
  for no benefit over (a) that this migration needs; worth reconsidering only if a later need
  for Corepack's own signature-checked downloads shows up.

Whichever is chosen, replace the `creates:` guard with one that compares the installed `yarn
--version` / `pnpm --version` against the pin (policy point 6) — the exact defect
MIGRATION3 found in `kind.yml` and `minikube.yml`, here hidden one layer deeper because the
guard's target path existed for a reason the playbook never created.

### `mise.yml`: the A5 form, the B3 destination, and a `$HOME` finding

**A5's key-form choice, decided by checking the key.** Unlike NodeSource's, mise's signing key
does expire:

```console
$ curl -s https://mise.jdx.dev/gpg-key.pub | gpg --show-keys --with-colons | grep ^pub
pub:-:4096:1:8B81C9D17413A06D:1704211734:1830442114::-:::scESC::::::23::0:
```

`1830442114` is 2028-01-02. Per MIGRATION3's rule ("pin the fingerprint always, pin the key bytes
only when the key has no expiry"), this is the `github-cli.yml`/`kubectl.yml` form: fetch the key
by URL each run (the module compares by checksum, so this stays idempotent) and assert the
fingerprint, `24853EC9F655CE80B48E6C3A8B81C9D17413A06D`, rather than pinning the bytes inline.
Both `amd64` and `arm64` `Packages` indices exist on `mise.jdx.dev/deb`, so `Architectures:` is
mapped from `ansible_architecture`, same as every other A5 playbook.

**The pin, checked live:** installed `2026.5.10`, candidate `2026.8.5` — confirm again at write
time, the same staleness warning every prior migration's upstream survey carries.

**B3's destination is a direct fit, and the repo already has the exact precedent.**
`eval "$(mise activate bash)"` is a PATH/env-rewriting hook, not a completion, so it is B3's
"aliases and `PATH` additions" row: `/etc/profile.d/mise.sh`, relying on the `/etc/bash.bashrc`
bootstrap `_multi-user/tools/modern-cli-tools.yml` already lays down (harmless, idempotent, to be
repeated here in case `mise.yml` is the first playbook run on a given host — the same reasoning
`kubectl.yml` and `helm.yml` already applied). Verification follows the same shape as
`modern-cli-tools.yml`'s fzf check: `mise activate bash` defines `mise()` and `_mise_hook()` as
shell functions, so a non-login interactive shell run as uid 65534 can assert `declare -F mise`
and `declare -F _mise_hook` the same way task 9 there asserts `__fzf_select__`.

**`mise` writes to `$HOME` on a plain `--version` — confirmed, and it changes how the playbook's
own post-install check has to work.** This is this migration's version of MIGRATION3's minikube
finding ("a tool that keeps per-user state may create it on any invocation, including one that
only prints a version"):

```console
$ rm -rf /tmp/mise-home-test && mkdir /tmp/mise-home-test
$ HOME=/tmp/mise-home-test mise --version
$ find /tmp/mise-home-test
/tmp/mise-home-test/.cache
/tmp/mise-home-test/.cache/mise
/tmp/mise-home-test/.cache/mise/latest-version
```

A self-update-check cache, written on the plainest possible invocation. Two consequences: the
playbook's own post-install version check must compare `dpkg-query`, not run `mise --version` as
root — running it as root would leave `/root/.cache/mise/latest-version` behind, a B2 violation
by the letter MIGRATION3 wrote it ("no task ... may write ... under any account's `$HOME`,
including the invoker's"). And the unprivileged smoke test needs the same scratch `HOME` every
other A4 verification in this repo already gets, cleaned up afterward. `mise doctor` was tried as
a stronger, A4-level-1/2 check (it inspects the real install rather than printing a bare version
string) and returned in under five seconds with no apparent network call — worth keeping as the
smoke test's main assertion, but **confirm it stays offline at write time**; a WARN line about a
newer version being available suggests it may consult cached or live update-check state, and if
that state is not present the check needs to tolerate the difference rather than fail on it.

## Order of work

Small enough for two waves rather than four:

1. **`core-tools.yml` and `nodejs.yml`.** Both are apt-only today and need no design decision
   beyond the two named above (the verify-command table for `core-tools.yml`; the Node version
   and the Yarn/pnpm mechanism for `nodejs.yml`). Write and verify both before `mise.yml`, so the
   A5/B3 pattern below has two more `_multi-user/core/` playbooks already using the shared
   `/etc/bash.bashrc` bootstrap to check consistency against.
2. **`mise.yml`.** Depends on nothing from wave 1 except the bootstrap task's idempotency (proven
   by whichever of `core-tools.yml`/`nodejs.yml` runs first not being the very first `_multi-user/`
   playbook on a given host — in practice already proven repo-wide since 2026-08-11). Goes last
   because it is the one playbook here with a genuine relocation (the `~/.bashrc` line) rather
   than pure hardening, and because its `$HOME`-on-`--version` finding is worth having the other
   two playbooks' verification pattern already settled before writing its smoke test around it.

## Procedure

MIGRATION.md's [ten-step procedure](MIGRATION.md#procedure) and MIGRATION2's/MIGRATION3's
additions apply unchanged, with one more specific to this directory:

- **Before step 6 (write the playbook),** for `core-tools.yml` confirm every "expected verify
  command" in the table above against the actual installed binary (`--help` or its manpage), not
  from memory — several are marked medium/low confidence above precisely because they were not
  checked against a running instance while writing this plan.

## Migration status

| Source playbook | Old mechanism | Target mechanism | Pinned | Status |
| --- | --- | --- | --- | --- |
| `core-tools.yml` | apt, unpinned | apt, pinned, per-package verify | 19 packages, see the playbook's `vars` | Verified (localhost) |
| `nodejs.yml` | NodeSource setup script, unpinned; Corepack shims mistaken for Yarn/pnpm | `deb822_repository`, pinned; Yarn/pnpm via `npm install -g` per decision (a) | nodejs 24.19.0-1nodesource1, yarn 1.22.22, pnpm 11.21.0 | Verified (localhost) |
| `mise.yml` | vendor apt repo (`.list` + shell dearmor), unpinned; `mise activate` in `~/.bashrc` | `deb822_repository` (URL key form), pinned; activation in `/etc/profile.d/mise.sh` | 2026.8.6 | Verified (localhost) |

Every row is also **retired**: none of the source playbooks named in the first column still
exists, each having been deleted on 2026-08-16 once its successor was verified, and `core/` was
removed with the last of them. The column is kept because it is what each migrated playbook is a
successor *to*, and every playbook's header comment still refers to it by name — as do the tasks
that clean up after it, which are the one part of this migration that outlives the source:
`nodejs.yml` and `mise.yml` each remove the apt source their predecessor wrote
(`nodesource.list`, `mise.list`) on hosts where the predecessor ran; `core-tools.yml` has no such
task because its predecessor left no state beyond the apt packages themselves, which the
successor's own pinned install already supersedes. `git log --diff-filter=D -- core/` recovers
any of them.

All three were run to `failed=0` against `localhost`, re-run a second time to confirm
`changed=` only the scratch-`HOME` create/remove every other `_multi-user/` playbook shows on a
re-run, and checked clean under `--check`. Same two caveats as every prior migration: ansible-core
2.20 only, `ansible_connection=local` only — neither the 24.04 control node nor the SSH/`ubuntu`
path has been exercised.

**`mise_version` moved mid-session, which is the argument for checking upstream at write time
rather than trusting this document.** The pin was first set to `2026.8.5` (`apt-cache policy
mise`'s candidate when this plan was written, 2026-08-14) and failed to install a few minutes
later with "no available installation candidate": upstream had published `2026.8.6` in the
interim and apt's candidate moved with it. Re-checking and pinning `2026.8.6` fixed it
immediately. The underlying mechanism (`apt`'s `allow_downgrade: true` synthesizing a
priority-1001 version pin) is necessary but not sufficient on this host's `python3-apt`
(3.1.0ubuntu1) whenever the requested version is not also the current apt candidate — reproduced
directly against `apt_pkg.Policy.get_candidate_ver()`, independently of Ansible, while plain
`apt-get install <pkg>=<version> --allow-downgrades` resolves the identical request correctly.
This is not particular to `mise.yml` or `nodejs.yml` (both hit it while testing an artificial
downgrade during verification): every `_multi-user/` playbook that pins an apt package the same
way carries the same exposure, and none of the prior "Verified" rows in MIGRATION.md/2/3 are
known to have exercised a genuine downgrade of an already-different-and-newer-installed package
through the module itself. It does not affect the normal case any of these playbooks is written
for — installing the pinned version onto a host with an older or no package at all, which is
what was actually verified in every row above.

**Two more findings only visible by running the playbooks, not by reading the source.** First,
`cowsay`'s Ubuntu package lives in `/usr/games`, which sudo's default `secure_path` does not
include — `core-tools.yml` calls it by absolute path rather than relying on `PATH`. Second, every
unprivileged smoke test in this directory needed an explicit `chdir` into its scratch `HOME` that
an early draft omitted: `git lfs`/`git secret` (in `core-tools.yml`) and both `yarn` and `pnpm`
(in `nodejs.yml`, the latter walking up from cwd looking for an rc file) all stat or scan the
current directory on startup, and an unprivileged uid cannot even stat this repository's checkout
path — the same class of defect MIGRATION2.md documented for `gcx-cli.yml`'s cwd read, recurring
here in tools this migration didn't itself write.

**A cosmetic defect in the `msg: >-` + `join('\n')` summary pattern several already-"Verified"
`_multi-user/` playbooks use (`docker.yml`, `kubectl.yml`, `github-cli.yml`, and this
migration's own first drafts of `nodejs.yml`/`mise.yml`).** Confirmed directly: a `'\n'` written
inside a YAML folded (`>-`) scalar never reaches Jinja as an escape sequence — YAML block scalars
do not process backslash escapes at all, so the two characters stay literal, and `join('\n')`
prints one line of visible backslash-n text instead of a multi-line summary. This is not the
`trim_blocks` defect MIGRATION.md already found and fixed with the same-looking `{{ '\n' }}`
idiom — that fix works only when the surrounding scalar is YAML **double-quoted** (as in
`modern-cli-tools.yml`'s working example), because it is YAML's own quote parsing that turns
`\n` into a real newline before Jinja ever sees it, not Jinja's. The fix used here avoids the
whole class: hand `ansible.builtin.debug`'s `msg` a real Jinja **list** built with `+` and
`ternary(...)` and skip `join()` entirely — the module already prints one line per list element,
confirmed working inside a `>-` scalar with no escaping needed at all. Worth applying to the
already-"Verified" playbooks named above the next time one of them is touched; none of their
summary text affects `failed=`, so this was never going to surface as a run failure.

## Known follow-ups

- ~~**Retiring `core/`.**~~ **Done 2026-08-16.** All three originals and the directory's README
  were deleted, on the gate `tool/`, `cloud-cli/` and `container/` passed: every successor
  verified against a real host. Retiring `core/` retired *the entire legacy tree* along with it —
  nothing named `core/`, `tool/`, `cloud-cli/`, `container/`, `services/` or `gui-tools/` remains
  anywhere in the repo, only `_multi-user/` and `_personal/`. That is the point at which the two
  follow-ups below, left open by MIGRATION3.md as hypothetical, stop being hypothetical.
- **The retirement gate is weaker than the word "verified" suggests, and this migration
  inherited it rather than fixing it.** All three playbooks here were verified on `localhost`
  alone, under ansible-core 2.20 alone, with no SSH path and no `remote_user` exercised — exactly
  the evidence `container/` was retired on. `ws01`/`ws02` have still never been provisioned by
  either generation. This plan called for fixing it (run at least one of the three from a 24.04
  control node over SSH, the check [MIGRATION2's scope note](MIGRATION2.md#scope) asked for),
  **and that run was never performed** — not before the deletion, and not since. So the item does
  not close with the directory; it moves forward. It now applies to all 34 `_multi-user/`
  playbooks (all of `_multi-user/tools/`, `_multi-user/cloud-cli/`, `_multi-user/container/` and
  `_multi-user/core/` — see [the count](README.md#multi-user-34)), and the cheapest way to
  discharge it is still one playbook, one 24.04 control node, one remote host.
- **Renaming `_multi-user/`.** The underscore has meant *staging*, sorting the tree apart from
  the live single-user directories it would replace, since MIGRATION.md. Those directories are
  gone now — the legacy tree does not exist at all — so the prefix marks a distinction that no
  longer exists, on all 34 of the repo's playbooks. Dropping it is cheaper than it looks —
  `ansible.cfg`'s `inventory` is relative and does not move — but it rewrites the `cd _multi-user`
  line in every documented command, in five `README.md` files (the root one plus `tools/`,
  `cloud-cli/`, `container/` and `core/` under `_multi-user/`) and in `ansible.cfg`'s own header
  comment. **The `_personal/` half of this question closed itself on 2026-08-16, the same day:**
  it did not earn the stated reason to keep its own underscore that this bullet left room for —
  it was retired outright instead, per-identity work ruled out of scope for the whole repo rather
  than kept staged under a different name (see
  [Retired: `_personal/`](README.md#retired-_personal)). `_multi-user/` is now the only
  underscore tree left, so this rename, if it happens, has no sibling decision to make alongside
  it any more. Worth doing as its own change rather than as the tail of this migration.
- **`~/.bashrc`'s `mise` block, left behind on any host that ran the source playbook.** Same
  shape as MIGRATION3's `kubectl`/`helm`/`kind`/`minikube` completion blocks and `xhost` lines:
  deleting `core/mise.yml` removed nothing already written into an account's `~/.bashrc`. On
  `localhost` that block is still at `~/.bashrc:133-135` as of the retirement. Whether the
  migrated playbook should remove it (a `blockinfile` with `state: absent` against an explicit
  user list) is the same open question MIGRATION3 left open for its own six blocks, for the same
  reason: it is the opposite of B2, and only argued for by nothing else in the repo ever taking
  it out.
- ~~**Bare `ansible_architecture`.**~~ **Done.** `nodejs.yml` and `mise.yml` were written using
  `ansible_facts['architecture']` from the start, per MIGRATION2's and MIGRATION3's follow-up
  note, so neither adds to the outstanding repo-wide pass, which still has only `aws-cli.yml` and
  the `_multi-user/tools/` playbooks to touch.
