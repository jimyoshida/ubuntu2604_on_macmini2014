#!/bin/bash
# Setup passwordless sudo for the current user
# This is useful for running Ansible playbooks without password prompts

set -e

USER=$(whoami)
SUDOERS_FILE="/etc/sudoers.d/99-${USER}-nopasswd"

echo "Setting up passwordless sudo for user: $USER"
echo ""
echo "This will create: $SUDOERS_FILE"
echo "Content: $USER ALL=(ALL) NOPASSWD:ALL"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Create the sudoers file (requires current sudo password)
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 0440 "$SUDOERS_FILE"

echo "Done! You can now run sudo commands without a password."
echo "Run the playbook with: ansible-playbook agent-base.yml"
