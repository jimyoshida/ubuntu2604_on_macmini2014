#!/bin/bash

# jenkins-agent.yml
export JENKINS_URL=           # Controller URL, e.g. http://controller:8080 — required
export JENKINS_AGENT_NAME=    # Node name as configured on the controller — required
export JENKINS_AGENT_SECRET=  # Agent secret from the controller node page — required
export JENKINS_AGENT_USER=    # Local user the agent service runs as — required
export JENKINS_AGENT_WORKDIR= # Agent work dir (default: <user home>/jenkins-agent)
