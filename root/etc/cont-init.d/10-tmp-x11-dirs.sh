#!/bin/bash
set -euo pipefail

# Xorg refuses to create /tmp/.X11-unix unless running as root.
# Create it early so both Xorg and X clients behave normally.
mkdir -p /tmp/.X11-unix /tmp/.ICE-unix
chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix

# Best-effort ownership; permissions are what matter here.
chown root:root /tmp/.X11-unix /tmp/.ICE-unix 2>/dev/null || true

echo "[steam-selkies] ensured /tmp/.X11-unix and /tmp/.ICE-unix"