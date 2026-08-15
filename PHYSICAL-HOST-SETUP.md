# Physical Host Setup (Non-EC2)

Manual steps for a host these playbooks no longer configure. Most sections below were removed
from `core/agent-base.yml` on 2026-08-14 (see
[_multi-user/core/README.md](_multi-user/core/README.md#core-toolsyml) and
`git log --all --full-history -- core/agent-base.yml core/core-tools.yml`) on the assumption that
the target already satisfies them or doesn't need them. That assumption holds for an AWS EC2
instance — cloud-init sets the hostname, the AMI ships `sshd` enabled, there is no lid or suspend
to fight on a VM, and there is no desktop session to blank or lock. None of it holds for a fresh
physical-PC Ubuntu install, so if that's the target, work through whichever sections below apply
after `_multi-user/core/core-tools.yml` (`core/core-tools.yml` until it was retired on
2026-08-16 per [MIGRATION4.md](MIGRATION4.md)) and before treating the box as ready. The
[Samba](#samba-file-sharing-optional)
section is different: `core/samba.yml` wasn't removed for being EC2-redundant, it was retired
outright as out of scope (see
[Retired: `core/samba.yml`](README.md#retired-coresambayml)) — it's here because sharing a home
directory over SMB is still something a physical LAN workstation may want, EC2 or not.

Every command needs root (`sudo`) unless noted otherwise.

## Hostname

```bash
sudo hostnamectl set-hostname <hostname>
sudo sed -i 's/^127\.0\.1\.1.*/127.0.1.1 <hostname>/' /etc/hosts
# if no 127.0.1.1 line exists yet:
echo '127.0.1.1 <hostname>' | sudo tee -a /etc/hosts
```

## SSH server

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

Keep sessions alive through long idle periods (60s keepalive probes, up to 720 missed probes
≈ 12h before the server drops the connection):

```bash
sudo sed -i 's/^#\?ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?ClientAliveCountMax.*/ClientAliveCountMax 720/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Client-side key setup (`~/.ssh` permissions, `authorized_keys`) is
[`setup-passwordless-ssh.sh`](setup-passwordless-ssh.sh), not this doc — see
[Passwordless SSH Setup](README.md#passwordless-ssh-setup).

## Avahi (mDNS discovery)

Only needed if other hosts on the LAN should find this one at `<hostname>.local`, or if you want
to browse for other `.local` services from here.

```bash
sudo apt install -y avahi-daemon avahi-utils
sudo systemctl enable --now avahi-daemon
```

Restrict which interfaces Avahi advertises on/listens on (skip this to allow all):

```bash
sudo sed -i 's/^#\?allow-interfaces=.*/allow-interfaces=<iface1,iface2>/' /etc/avahi/avahi-daemon.conf
sudo systemctl restart avahi-daemon
```

Useful commands once running:

```bash
avahi-browse -a -t                          # Discover all mDNS services on the LAN (one-shot)
avahi-browse _ssh._tcp -t                   # Find SSH-advertised hosts
avahi-resolve-host-name hostname.local      # Resolve a .local hostname to IP
avahi-resolve-address 192.168.x.x           # Reverse-resolve IP to .local name
```

## systemd-resolved

```bash
sudo systemctl enable --now systemd-resolved
```

## Disable sleep/suspend (headless operation)

Prevents the box from suspending itself when nobody's at the console:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

## Disable screen blanking and GNOME lock/power management

Only relevant if a desktop session actually runs on this host (an EC2 instance, and most
SSH-only boxes, has none).

X11 session (`~/.xprofile` and `~/.xsessionrc`, no root needed):

```bash
for f in ~/.xprofile ~/.xsessionrc; do
  printf '# Disable automatic screen blanking\nxset s off\nxset -dpms\n' >> "$f"
done
```

GNOME (no root needed; run inside the graphical session, not over plain SSH):

```bash
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-timeout 0
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
```

Ignore lid/idle actions system-wide via logind (relevant for a laptop used headless with the lid
closed):

```bash
sudo tee -a /etc/systemd/logind.conf >/dev/null <<'EOF'
IdleAction=ignore
LidSwitchIgnoreInhibited=no
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOF
sudo systemctl restart systemd-logind
```

## Shell niceties (optional)

A small `~/.bashrc` addition the old playbook made — cosmetic, add only if wanted:

```bash
# git branch in the prompt
cat >> ~/.bashrc <<'EOF'
parse_git_branch() {
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}
PS1="\[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[33m\] \$(parse_git_branch)\[\033[00m\]$ "
EOF
```

## Disable IPv6 on a NetworkManager connection (optional)

Only meaningful where NetworkManager owns the interface (typically not the case on an EC2
instance, which uses netplan/systemd-networkd directly). Replace `<connection-name>` with the
output of `nmcli connection show`:

```bash
nmcli connection modify "<connection-name>" ipv6.method disabled
nmcli connection up "<connection-name>"
```

## journald: low-disk-io tuning (optional)

Caps journal disk usage and syncs less aggressively — worth doing on a box with limited or slow
local storage; an EC2 instance backed by fast EBS/instance storage generally doesn't need it.

```bash
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/low-io.conf >/dev/null <<'EOF'
[Journal]
# Limit disk usage to 500MB
SystemMaxUse=500M

# Keep only 3 days of logs
MaxRetentionSec=3d

# Sync to disk less frequently (5 minutes instead of default)
SyncIntervalSec=5m

# Limit individual log file size
SystemMaxFileSize=64M

# Maximum number of log files to keep
SystemMaxFiles=8

# Reduce rate limiting to drop more logs during bursts
RateLimitIntervalSec=30s
RateLimitBurst=1000

# Compress logs to save space
Compress=yes
EOF
sudo systemctl restart systemd-journald
sudo journalctl --vacuum-size=500M
```

## Samba file sharing (optional)

Shares the current user's home directory over SMB — useful for a physical workstation on a LAN
that other machines (e.g. a macOS laptop) need to browse files on. Not EC2-specific: an EC2
instance could run this too, it just rarely has anything on the same LAN to share with.

```bash
sudo apt install -y samba
sudo smbpasswd -a <user>   # prompts for a Samba password, separate from the account password
```

Restrict Samba to specific interfaces (skip this to listen on all):

```bash
sudo tee -a /etc/samba/smb.conf >/dev/null <<'EOF'

[global]
   interfaces = <iface1 iface2>
   bind interfaces only = yes
EOF
```

Add a `[homes]` share — not browseable, read-write, and restricted so only the owning user can
open their own share (`valid users = %S`):

```bash
sudo tee -a /etc/samba/smb.conf >/dev/null <<'EOF'

[homes]
   comment = Home Directories
   browseable = no
   read only = no
   create mask = 0750
   force create mode = 0550
   directory mask = 0750
   force directory mode = 0550
   valid users = %S
EOF
```

```bash
sudo systemctl enable --now smbd nmbd
```

Connecting from macOS: in Finder, press `⌘K` and enter `smb://<host-ip>`.

Managing the service:

```bash
systemctl status smbd nmbd    # Check status
systemctl restart smbd nmbd   # Restart
journalctl -u smbd -f         # View logs
```
