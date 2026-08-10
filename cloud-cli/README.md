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

The one playbook not yet migrated. It is still single-user in the way MIGRATION2.md
describes: it renders the **invoking shell's** `$JENKINS_URL` into
`/usr/local/bin/jenkins-cli`, a file every account executes, so one person's environment
silently becomes everyone's default. Migrating it is blocked on the `env-tmpl.sh` decision
below.

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

## env-tmpl.sh

A template of the environment variables the playbooks here used to read. It is kept because
`jenkins-cli.yml` still reads its shell environment, and because
[MIGRATION2.md's A1](../MIGRATION2.md#policy-amendments) plans to split it in two — the
shared, non-secret half applied by the playbooks, and a per-user
`~/.config/cloud-cli/env.sh` at mode `0600` for the tokens. That split is what
`jenkins-cli.yml` is waiting on.

**None of the migrated playbooks reads this file, or any environment variable.** They take
endpoint configuration from `vars:` overridable with `-e`, and they set no secret anywhere:
`/etc/environment` is world-readable, which on a shared workstation is exactly the problem.
Each account configures its own identity — the commands are printed by each playbook's
closing summary.

Two entries in the template name variables **no tool actually reads** — they were the old
playbooks' own inputs, used only to interpolate an instruction into a message. Verified
against the binaries:

| In the template | Reality |
| --- | --- |
| `JIRA_URL`, `JIRA_LOGIN` | jira-cli reads neither. Both come from `~/.config/.jira/.config.yml`, written by `jira init`. |
| `AZURE_DEVOPS_ORG`, `AZURE_DEVOPS_PROJECT` | The extension reads `AZURE_DEVOPS_EXT__DEFAULTS_ORGANIZATION` / `AZURE_DEVOPS_EXT__DEFAULTS_PROJECT` (note the double underscore). |

The rest are real: `JENKINS_URL`, `GRAFANA_SERVER`, `INFLUX_HOST`, `INFLUX_ORG` and
`VAULT_ADDR` are all read by their tools, and every `*_TOKEN` / `*_PAT` is a secret that
belongs in `$HOME` at mode `0600` and nowhere else.
