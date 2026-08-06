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
