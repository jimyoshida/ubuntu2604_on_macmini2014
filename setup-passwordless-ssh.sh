#!/bin/bash
# Setup SSH public key authentication for the current user
# Run it after uploading id_rsa and id_rsa.pub to ~/.ssh. Nothing here needs
# sudo, and every step is idempotent, so re-running is safe.
#
# Ownership is not set: everything below lives in $HOME and is created by this
# script, so it already belongs to whoever runs it.

set -euo pipefail

SSH_DIR="${HOME}/.ssh"
PRIVATE_KEY="${SSH_DIR}/id_rsa"
PUBLIC_KEY="${SSH_DIR}/id_rsa.pub"
SSH_CONFIG="${SSH_DIR}/config"
AUTHORIZED_KEYS="${SSH_DIR}/authorized_keys"

echo "Setting up SSH public key authentication for user: $(whoami)"
echo "Directory: $SSH_DIR"
echo ""

# The directory itself. The umask makes it 0700 from the moment it exists
# rather than after a chmod; the chmod is for a directory that already existed
# with looser permissions.
(umask 0077 && mkdir -p "$SSH_DIR")
chmod 0700 "$SSH_DIR"

# Private key: owner-only, or ssh refuses to use it at all.
if [[ -f $PRIVATE_KEY ]]; then
    chmod 0600 "$PRIVATE_KEY"
    echo "  id_rsa           0600"
else
    echo "  id_rsa           not found"
fi

if [[ -f $PUBLIC_KEY ]]; then
    chmod 0644 "$PUBLIC_KEY"
    echo "  id_rsa.pub       0644"
else
    echo "  id_rsa.pub       not found"
fi

# The client config is optional; only touch it if this host has one.
if [[ -f $SSH_CONFIG ]]; then
    chmod 0600 "$SSH_CONFIG"
    echo "  config           0600"
fi

# authorized_keys has to exist before anything can be appended to it. Create it
# only when missing, so re-running leaves an existing file's mtime alone.
[[ -f $AUTHORIZED_KEYS ]] || touch "$AUTHORIZED_KEYS"
chmod 0600 "$AUTHORIZED_KEYS"
echo "  authorized_keys  0600"

# Authorize our own public key, matching the whole line so a re-run is a no-op.
if [[ -f $PUBLIC_KEY ]]; then
    key_line=$(head -n 1 "$PUBLIC_KEY" | sed -e 's/[[:space:]]*$//')

    echo ""
    if grep -qxF "$key_line" "$AUTHORIZED_KEYS"; then
        echo "Public key already authorized; authorized_keys unchanged."
    else
        # If the last line of an existing file has no newline, appending would
        # splice our key onto the end of it.
        if [[ -s $AUTHORIZED_KEYS && -n $(tail -c 1 "$AUTHORIZED_KEYS") ]]; then
            printf '\n' >>"$AUTHORIZED_KEYS"
        fi
        printf '%s\n' "$key_line" >>"$AUTHORIZED_KEYS"
        echo "Public key appended to authorized_keys."
    fi
fi

if [[ ! -f $PRIVATE_KEY || ! -f $PUBLIC_KEY ]]; then
    echo ""
    echo "WARNING: id_rsa and/or id_rsa.pub not found in $SSH_DIR."
    echo "         Upload the key pair there, then run this script again."
    echo "         Permissions on everything else were still applied."
    exit 0
fi

echo ""
echo "Done! Test from the client with: ssh $(whoami)@$(hostname)"
