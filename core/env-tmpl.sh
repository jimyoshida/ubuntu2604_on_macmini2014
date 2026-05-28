#!/bin/bash

# agent-base.yml
export HOSTNAME=            # Target hostname to set on the machine
export AVAHI_INTERFACES=    # Network interfaces for Avahi mDNS (e.g. enp3s0f0); empty = all
export NM_CONNECTION=       # NetworkManager connection name (default: netplan-enp3s0f0)

# x11vnc.yml
export VNC_PASSWORD=        # VNC password — required
