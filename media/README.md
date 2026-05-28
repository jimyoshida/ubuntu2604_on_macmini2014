# Media

## jellyfin.yml

Jellyfin media server setup

```bash
ansible-playbook media/jellyfin.yml
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

---

## samba.yml

Samba file sharing setup (home directory share)

```bash
SAMBA_PASSWORD=<password> ansible-playbook media/samba.yml
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
