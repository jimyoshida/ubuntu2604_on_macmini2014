# Cloud CLI Tools

## aws-cli.yml

Install AWS CLI

```bash
ansible-playbook cloud-cli/aws-cli.yml
```

## azure-cli.yml

Install Azure CLI

```bash
ansible-playbook cloud-cli/azure-cli.yml
```

## gcloud-cli.yml

Install Google Cloud CLI

```bash
ansible-playbook cloud-cli/gcloud-cli.yml
```

## github-cli.yml

Install GitHub CLI

```bash
ansible-playbook cloud-cli/github-cli.yml
```

## gitlab-cli.yml

Install GitLab CLI

```bash
ansible-playbook cloud-cli/gitlab-cli.yml
```

## jenkins-cli.yml

Install Jenkins CLI (`jenkins-cli.jar`) from a running Jenkins instance, with a wrapper script at `/usr/local/bin/jenkins-cli`.

```bash
# Default (http://localhost:8080)
ansible-playbook cloud-cli/jenkins-cli.yml

# Custom Jenkins URL
JENKINS_URL=http://jenkins.example.com:8080 ansible-playbook cloud-cli/jenkins-cli.yml
```

The wrapper reads the following environment variables:

| Variable            | Description                        |
| ------------------- | ---------------------------------- |
| `JENKINS_URL`       | Jenkins server URL                 |
| `JENKINS_USER_ID`   | Jenkins username                   |
| `JENKINS_API_TOKEN` | Jenkins API token                  |

### nginx proxy requirement

Jenkins CLI uses WebSocket by default (modern Jenkins 2.x). If Jenkins is behind an nginx reverse proxy, the proxy config must forward WebSocket upgrade headers:

```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

Without these, the CLI handshake fails with HTTP 400.

## azure-devops-cli.yml

Install Azure DevOps CLI (the `azure-devops` extension for Azure CLI). Installs Azure CLI as a prerequisite.

```bash
# Basic install
ansible-playbook cloud-cli/azure-devops-cli.yml

# With default org and project pre-configured
AZURE_DEVOPS_ORG=https://dev.azure.com/YOUR_ORG \
AZURE_DEVOPS_PROJECT=YOUR_PROJECT \
ansible-playbook cloud-cli/azure-devops-cli.yml
```

After installation, authenticate and configure defaults:

```bash
az login
az devops configure --defaults organization=https://dev.azure.com/YOUR_ORG project=YOUR_PROJECT
```

The following environment variables are supported:

| Variable                  | Description                              |
| ------------------------- | ---------------------------------------- |
| `AZURE_DEVOPS_ORG`        | Default organization URL (configure step) |
| `AZURE_DEVOPS_PROJECT`    | Default project name (configure step)    |
| `AZURE_DEVOPS_EXT_PAT`    | Personal access token for non-interactive auth |

## jira-cli.yml

Install Jira CLI (`ankitpokhrel/jira-cli`) via Homebrew. Requires Homebrew (`core/homebrew.yml`).

```bash
ansible-playbook cloud-cli/jira-cli.yml
```

After installation, run `jira init` to configure your instance interactively:

```bash
jira init --installation cloud --server https://YOUR_ORG.atlassian.net --login your@email.com --project YOUR_PROJECT
```

The following environment variables are supported:

| Variable             | Description                                                |
| -------------------- | ---------------------------------------------------------- |
| `JIRA_API_TOKEN`     | API token (basic auth) or PAT (bearer auth) — required     |
| `JIRA_AUTH_TYPE`     | `basic` (default), `bearer` (PAT), or `mtls`               |
| `JIRA_CONFIG_FILE`   | Path to config file (default: `~/.config/.jira/.config.yml`) |
