#!/bin/bash
set -euo pipefail

# LinuxServer Selkies images typically run the Wayland compositor on wayland-1.
# Selkies uses a configurable socket index for running Wayland helper commands
# (e.g. wlr-randr) and for input injection.
#
# If Selkies targets wayland-0 while the compositor is actually on wayland-1,
# the UI can look "connected" but appear frozen/black (FPS stays 0) because
# input + Wayland commands are sent to the wrong socket.

if [ "${PIXELFLUX_WAYLAND:-}" != "true" ]; then
  exit 0
fi

# Respect an explicit user override.
if [ -n "${SELKIES_WAYLAND_SOCKET_INDEX:-}" ]; then
  exit 0
fi

mkdir -p /etc/cont-env.d
printf '%s' "1" >/etc/cont-env.d/SELKIES_WAYLAND_SOCKET_INDEX

echo "[steam-selkies] PIXELFLUX_WAYLAND=true -> SELKIES_WAYLAND_SOCKET_INDEX=1"
