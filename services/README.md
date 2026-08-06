# Services

## vault.yml

Install HashiCorp Vault OSS

```bash
ansible-playbook services/vault.yml
```

Installs Vault from the official HashiCorp APT repository (pinned to `noble` — Ubuntu 26.04 `resolute` is not yet supported upstream). Configures file storage at `/opt/vault/data`, enables the UI, and starts the `vault` systemd service on port `8200`. Adds `VAULT_ADDR=http://127.0.0.1:8200` to `~/.bashrc`.

**After installation:**

```bash
source ~/.bashrc

# 1. Initialize (run once — save the output securely)
vault operator init

# 2. Unseal (run 3 times with 3 different unseal keys from above)
vault operator unseal

# 3. Log in with the root token
vault login <root-token>
```

UI is available at `http://127.0.0.1:8200/ui`.

> **Note:** TLS is disabled in the default config. For production use, configure a certificate in `/etc/vault.d/vault.hcl` and remove `tls_disable = 1`.

## n8n.yml

Install n8n Workflow Automation

```bash
ansible-playbook services/n8n.yml
```

**Prerequisites:**
- System-wide Node.js installed via `core/nodejs.yml`
  - version manager-managed Node.js will cause the playbook to fail

Installs n8n globally via npm and starts the `n8n` systemd service on port `5678`. Workflow data and SQLite database are stored in `/var/lib/n8n`. n8n generates and manages its own encryption key in `/var/lib/n8n/.n8n/config` on first start.

**Optional environment variables:**
- `N8N_PORT` — port to listen on (default: `5678`)

**After installation:**

The n8n UI is available at `http://localhost:5678`. On first access you will be prompted to create an admin account.

```bash
# Check service status
systemctl status n8n

# View logs
journalctl -u n8n -f
```

> **Note:** Back up `/var/lib/n8n/.n8n/config` — it contains the encryption key for stored credentials.

## jellyfin.yml

Jellyfin media server setup

```bash
ansible-playbook services/jellyfin.yml
```

This playbook:
- Adds the official Jellyfin apt repository
- Installs Jellyfin
- Enables and starts the `jellyfin` systemd service

After installation, open the web UI to complete the initial setup wizard:

```
http://localhost:8096
```

**Managing the service:**
```bash
systemctl status jellyfin    # Check status
systemctl restart jellyfin   # Restart
journalctl -u jellyfin -f    # View logs
systemctl stop jellyfin      # Stop
```

## samba.yml

Samba file sharing setup (home directory share)

```bash
SAMBA_PASSWORD=<password> ansible-playbook services/samba.yml
```

**Environment variables:**

| Variable | Required | Description |
|----------|----------|-------------|
| `SAMBA_PASSWORD` | Yes | Samba password for the current user |
| `SAMBA_INTERFACES` | No | Network interfaces to bind (e.g. `lo eth0`). If unset, Samba listens on all interfaces |

This playbook:
- Installs Samba
- Sets the Samba password for the current user
- Configures a `[homes]` share (browseable, read-write, accessible only by the owner)
- Optionally restricts Samba to specific network interfaces via `SAMBA_INTERFACES`
- Enables and starts `smbd` and `nmbd`

**Connecting from macOS:**

In Finder, press `⌘K` and enter:
```
smb://<host-ip>
```

**Managing the service:**
```bash
systemctl status smbd nmbd    # Check status
systemctl restart smbd nmbd   # Restart
journalctl -u smbd -f         # View logs
```

## freshrss.yml

Install FreshRSS via Docker

```bash
ansible-playbook services/freshrss.yml
```

**Prerequisites:**

- Docker must be installed first (run `container/docker.yml`)

This playbook:

- Verifies Docker is installed
- Creates persistent storage directories for FreshRSS configuration, data, and extensions
- Sets up a Docker network for the container
- Deploys FreshRSS image on port `8081`
- Waits for the service to be ready before reporting success

**After installation:**

FreshRSS web UI is available at `http://127.0.0.1:8081`. Follow the setup wizard to configure your feeds and preferences. Persistent data is stored at `~/freshrss-data/`.

**Managing the container:**

```bash
docker stop freshrss      # Stop the container
docker start freshrss     # Start the container
docker logs freshrss      # View container logs
```
