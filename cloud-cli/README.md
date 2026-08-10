# Cloud CLI Tools

**Twelve of the thirteen playbooks that lived here have been migrated and deleted.** Their
successors are in [`_multi-user/cloud-cli/`](../_multi-user/cloud-cli/README.md), which
installs the same tools to root-owned system paths for **every** account on the box rather
than for whoever runs the playbook. See [MIGRATION2.md](../MIGRATION2.md) for what changed
per tool and why.

| Was here | Now |
| --- | --- |
| `aws-cli.yml`, `azure-cli.yml`, `azure-devops-cli.yml`, `gcloud-cli.yml`, `gcx-cli.yml`, `github-cli.yml`, `gitlab-cli.yml`, `influx-cli.yml`, `jira-cli.yml`, `opentofu.yml`, `prometheus-cli.yml`, `vault-cli.yml` | `_multi-user/cloud-cli/<same name>` |

The migrated playbooks are run differently — they push to a host instead of running on
`localhost`, so they take an inventory target:

```bash
cd _multi-user
ansible-playbook cloud-cli/aws-cli.yml -e host=<inventory host or group>
```

The originals are in git history if one is ever needed: `git log --diff-filter=D -- cloud-cli/`.

## jenkins-cli.yml

**Superseded by [`_multi-user/cloud-cli/jenkins-cli.yml`](../_multi-user/cloud-cli/README.md#jenkins-cliyml),
which is verified. Use that one.** This copy is kept only until the new build is proven on a
real host, exactly as the other twelve were.

Two reasons not to run this one:

- It renders the **invoking shell's** `$JENKINS_URL` into `/usr/local/bin/jenkins-cli`, a
  file every account executes, so one person's environment silently becomes everyone's
  default.
- It downloads `jenkins-cli.jar` **from a running Jenkins**, so it cannot install anything on
  a host with no Jenkins reachable, installs whatever version that server happens to be, and
  verifies nothing. The successor takes a pinned, checksum-verified jar from
  `repo.jenkins-ci.org` instead.

Install Jenkins CLI (`jenkins-cli.jar`) from a running Jenkins instance, with a wrapper
script at `/usr/local/bin/jenkins-cli`.

```bash
# Default (http://localhost:8080)
ansible-playbook cloud-cli/jenkins-cli.yml

# Custom Jenkins URL
JENKINS_URL=http://jenkins.example.com:8080 ansible-playbook cloud-cli/jenkins-cli.yml
```

### nginx proxy requirement

Jenkins CLI uses WebSocket by default (modern Jenkins 2.x). If Jenkins is behind an nginx reverse proxy, the proxy config must forward WebSocket upgrade headers:

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

Without these, the CLI handshake fails with HTTP 400.

### Per-user setup

The wrapper reads three variables **at run time**, from each user's own environment:

| Variable | Kind | What it does |
| --- | --- | --- |
| `JENKINS_URL` | shared, non-secret | Overrides the URL baked into the wrapper at install time. |
| `JENKINS_USER_ID` | per-identity | Jenkins username. Passed as `-auth <user>:<token>`. |
| `JENKINS_API_TOKEN` | **secret** | API token, generated in Jenkins under *Configure → API Token*. |

Put the two credential variables in a file only you can read, and source it from your own
shell. There is no template file in this repo to copy — deliberately: a tracked file that
looks like a place to write tokens is a file someone eventually commits with tokens in it.

```bash
umask 077
mkdir -p ~/.config/cloud-cli
cat > ~/.config/cloud-cli/env.sh <<'SH'
export JENKINS_USER_ID=your-jenkins-user
export JENKINS_API_TOKEN=your-api-token
SH
chmod 600 ~/.config/cloud-cli/env.sh
```

Then, in your own `~/.bashrc`:

```bash
[ -r ~/.config/cloud-cli/env.sh ] && . ~/.config/cloud-cli/env.sh
```

Check it works:

```bash
jenkins who-am-i        # or: jenkins-cli who-am-i
```

**Never put `JENKINS_API_TOKEN` in `/etc/environment`.** It is world-readable, so on a
shared workstation that hands your Jenkins identity to every account on the box. The same
goes for any other `*_TOKEN` or `*_PAT`. `JENKINS_URL` is not a secret and may be a
site-wide default in `/etc/environment` if every account really should point at the same
Jenkins — but this playbook does not put it there; it bakes it into the wrapper instead,
which is the defect that blocks its migration.
