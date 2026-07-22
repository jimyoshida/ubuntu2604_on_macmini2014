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

## jira-cli.yml

Install Jira CLI (`ankitpokhrel/jira-cli`) via Homebrew. Requires Homebrew (`core/homebrew.yml`).

```bash
ansible-playbook cloud-cli/jira-cli.yml
```

After installation, run `jira init` to configure your instance interactively:

```bash
jira init --installation cloud --server https://YOUR_ORG.atlassian.net --login your@email.com --project YOUR_PROJECT
```

## gcx-cli.yml

Install gcx (Grafana CLI) via Homebrew. Requires Homebrew (`core/homebrew.yml`).

```bash
ansible-playbook cloud-cli/gcx-cli.yml
```

After installation, authenticate with a service account token:

```bash
gcx login my-grafana --server https://YOUR_INSTANCE.grafana.net --token glsa_xxx --yes
```

Or set `GRAFANA_SERVER` / `GRAFANA_TOKEN` env vars for CI/CD, then verify with `gcx config check`.

## opentofu.yml

Install OpenTofu

```bash
ansible-playbook cloud-cli/opentofu.yml
```

Installs OpenTofu from the official apt repository. The apt package name is `tofu`; the binary is available as `tofu` after installation.

**After installation:**

```bash
tofu version
tofu init       # Initialize a working directory
tofu plan       # Preview infrastructure changes
tofu apply      # Apply changes
```

## prometheus-cli.yml

Install promtool and amtool

```bash
ansible-playbook cloud-cli/prometheus-cli.yml
```

Installs `promtool` (Prometheus config/rule validation and query CLI) from the Ubuntu apt repository. `amtool` (Alertmanager CLI) is bundled inside the `prometheus-alertmanager` package, so that package is also installed — but the Alertmanager daemon it ships is stopped and disabled immediately after, since this playbook is only for the CLI tools, not a running Alertmanager service.

Usage examples:

```bash
promtool check config /etc/prometheus/prometheus.yml   # Validate Prometheus config
promtool check rules /etc/prometheus/rules.yml          # Validate alerting/recording rules
promtool query instant http://localhost:9090 'up'       # Run an instant query
amtool check-config /etc/prometheus/alertmanager.yml    # Validate Alertmanager config
amtool alert query --alertmanager.url=http://localhost:9093  # List active alerts
amtool silence add alertname=Foo --alertmanager.url=http://localhost:9093  # Create a silence
```

**Note:** `amtool` commands that talk to a running Alertmanager (`alert`, `silence`) require an Alertmanager instance reachable at `--alertmanager.url` (default `http://localhost:9093`). This playbook does not deploy that service.

