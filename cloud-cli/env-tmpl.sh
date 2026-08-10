#!/bin/bash
#
# Environment template for the cloud-cli playbooks. Source it from your own
# shell; never commit a filled-in copy.
#
# Only jenkins-cli.yml still reads any of this. The other twelve playbooks have
# been migrated to _multi-user/cloud-cli/, which reads no environment variable
# at all: endpoint configuration comes from vars: overridable with -e, and no
# secret is written anywhere by a playbook. See MIGRATION2.md (A1/A2), which
# also plans to split this file into a shared, non-secret half and a per-user
# ~/.config/cloud-cli/env.sh at mode 0600 for the tokens.
#
# The tool names below are kept, rather than the deleted playbook filenames.
# Every *_TOKEN and *_PAT here is a SECRET: keep it in your own environment at
# mode 0600, never in /etc/environment, which is shared and world-readable.

# gcloud
export GOOGLE_CLOUD_PROJECT=   # Google Cloud project ID
export GOOGLE_CLOUD_LOCATION=  # Default region (e.g. asia-northeast1)

# jenkins-cli  (the one playbook still in cloud-cli/)
export JENKINS_URL=        # Jenkins server URL
export JENKINS_USER_ID=    # Jenkins username
export JENKINS_API_TOKEN=  # Jenkins API token

# az devops
# NOTE: AZURE_DEVOPS_ORG / AZURE_DEVOPS_PROJECT are NOT read by the CLI --
# they were the old playbook's own inputs. These are the real names (the
# double underscore is not a typo):
export AZURE_DEVOPS_EXT__DEFAULTS_ORGANIZATION=   # e.g. https://dev.azure.com/YOUR_ORG
export AZURE_DEVOPS_EXT__DEFAULTS_PROJECT=        # Default project name
export AZURE_DEVOPS_EXT_PAT=   # Personal access token for non-interactive auth

# jira
# NOTE: jira-cli reads neither JIRA_URL nor JIRA_LOGIN -- both live in
# ~/.config/.jira/.config.yml, written by `jira init`. They were the old
# playbook's own inputs and are dropped here.
export JIRA_API_TOKEN=    # Atlassian API token — used with basic auth on Jira Cloud

# influx
export INFLUX_HOST=       # InfluxDB server URL (e.g. http://localhost:8086)
export INFLUX_ORG=        # Default organization name
export INFLUX_TOKEN=      # API token

# vault
export VAULT_ADDR=        # Vault server URL (e.g. https://YOUR_VAULT_ADDR:8200)
export VAULT_TOKEN=       # Vault token

# gcx
export GRAFANA_SERVER=    # Grafana Cloud instance URL (e.g. https://YOUR_INSTANCE.grafana.net)
export GRAFANA_TOKEN=     # Service account token
