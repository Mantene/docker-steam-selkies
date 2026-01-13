#!/usr/bin/env bash
set -euo pipefail

# X11/ICE socket directories must be root-owned and sticky, otherwise Xwayland
# and session components (ksmserver) can fail or complain.

mkdir -p /tmp/.X11-unix /tmp/.ICE-unix || true

# Clear stale sockets that may have been created with wrong ownership.
rm -f /tmp/.X11-unix/X* /tmp/.ICE-unix/* >/dev/null 2>&1 || true

chown root:root /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true
chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true

echo "[steam-selkies] ensured /tmp/.X11-unix and /tmp/.ICE-unix ownership (root:root 1777)"
