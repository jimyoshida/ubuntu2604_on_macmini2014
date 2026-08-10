# Services

## vault.yml — removed 2026-08-10

There is no Vault playbook here any more, and no Vault server on this workstation. The
service was stopped and disabled and `/opt/vault` (file storage and the self-signed
certificate), `/etc/vault.d`, the `vault` system user and the `VAULT_ADDR` block in
`~/.bashrc` were all deleted. The storage was **not** backed up, so nothing is left to
restore: a future Vault would start from `vault operator init`.

The `vault` **package** is still installed, because the same package is also the CLI. The
client half is owned by
[`_multi-user/cloud-cli/vault-cli.yml`](../_multi-user/cloud-cli/README.md#vault-cliyml),
which installs `/usr/bin/vault` system-wide, configures no identity, and deliberately
leaves `vault.service` alone.

Why it went rather than being migrated: the playbook deployed a *server* that nothing in
this repo used, in a shape the multi-user work is explicitly removing — a `0.0.0.0:8200`
listener with `tls_disable = 1`, and `VAULT_ADDR` appended to whichever account happened to
run it. Deploying the servers these CLIs talk to is out of scope for that migration
(MIGRATION2.md), so there was nothing to migrate it into.

If a Vault server is wanted again, write it fresh rather than restoring this one, and keep
its apt repository on the `noble` suite so it agrees with `vault-cli.yml` — two entries for
one URI under different suites are two repositories to apt. (HashiCorp does publish
`resolute` and `plucky`; the pin is about agreement between playbooks, not about a missing
suite.)

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
