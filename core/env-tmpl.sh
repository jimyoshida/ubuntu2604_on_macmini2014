#!/bin/bash

# agent-base.yml
export HOSTNAME=            # Target hostname to set on the machine
export AVAHI_INTERFACES=    # Network interfaces for Avahi mDNS (e.g. enp3s0f0); empty = all
export NM_CONNECTION=       # NetworkManager connection name — required (e.g. netplan-enp3s0f0)

# x11vnc.yml
export VNC_PASSWORD=        # VNC password — required

# samba.yml
export SAMBA_PASSWORD=      # Samba user password — required
export SAMBA_INTERFACES=    # Network interfaces for Samba (e.g. lo enp3s0f0); empty = all
