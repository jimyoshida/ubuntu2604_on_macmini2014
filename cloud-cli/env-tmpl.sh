#!/bin/bash

# Jenkins CLI (cloud-cli/jenkins-cli.yml)
export JENKINS_URL=        # Jenkins server URL
export JENKINS_USER_ID=    # Jenkins username
export JENKINS_API_TOKEN=  # Jenkins API token

# Azure DevOps CLI (cloud-cli/azure-devops-cli.yml)
export AZURE_DEVOPS_ORG=       # Default organization URL (e.g. https://dev.azure.com/YOUR_ORG)
export AZURE_DEVOPS_PROJECT=   # Default project name
export AZURE_DEVOPS_EXT_PAT=   # Personal access token for non-interactive auth

# Jira CLI (cloud-cli/jira-cli.yml)
export JIRA_URL=          # Jira server URL (e.g. https://YOUR_ORG.atlassian.net)
export JIRA_API_TOKEN=    # API token (basic auth) or PAT (bearer auth) — required
export JIRA_AUTH_TYPE=    # basic (default), bearer (PAT), or mtls
export JIRA_CONFIG_FILE=  # Path to config file (default: ~/.config/.jira/.config.yml)
