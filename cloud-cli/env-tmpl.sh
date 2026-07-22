#!/bin/bash

# gcloud-cli.yml
export GOOGLE_CLOUD_PROJECT=   # Google Cloud project ID
export GOOGLE_CLOUD_LOCATION=  # Default region (e.g. asia-northeast1)

# jenkins-cli.yml
export JENKINS_URL=        # Jenkins server URL
export JENKINS_USER_ID=    # Jenkins username
export JENKINS_API_TOKEN=  # Jenkins API token

# azure-devops-cli.yml
export AZURE_DEVOPS_ORG=       # Default organization URL (e.g. https://dev.azure.com/YOUR_ORG)
export AZURE_DEVOPS_PROJECT=   # Default project name
export AZURE_DEVOPS_EXT_PAT=   # Personal access token for non-interactive auth

# jira-cli.yml
export JIRA_URL=          # Jira server URL (e.g. https://YOUR_ORG.atlassian.net)
export JIRA_LOGIN=        # Login email — required by jira init even with PAT auth
export JIRA_API_TOKEN=    # Atlassian API token — used with basic auth on Jira Cloud

# influx-cli.yml
export INFLUX_HOST=       # InfluxDB server URL (e.g. http://localhost:8086)
export INFLUX_ORG=        # Default organization name
export INFLUX_TOKEN=      # API token
