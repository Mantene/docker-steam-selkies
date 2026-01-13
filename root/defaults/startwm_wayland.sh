#!/usr/bin/env bash
set -euo pipefail

# This script is used by linuxserver/baseimage-selkies when PIXELFLUX_WAYLAND=true.
# The base image provides a Wayland compositor (labwc) and a Wayland socket.
# Running Plasma Wayland as a second compositor often fails in containers due to
# DRM/KMS access requirements; instead we run Plasma X11 on Xwayland.

log() {
  echo "[steam-selkies][startwm_wayland] $*" | tee -a /config/steam-selkies.log >/dev/null 2>&1 || true
}

can_write() {
  local p="$1"
  ( : >>"$p" ) >/dev/null 2>&1
}

# Session hints
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=KDE
export KDE_FULL_SESSION=true

# Selkies conventions: compositor socket is typically wayland-1
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

# Runtime dir: base images commonly use /config/.XDG
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/config/.XDG}
mkdir -p "${XDG_RUNTIME_DIR}" || true
chmod 700 "${XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true

log "Running as: $(id -un 2>/dev/null || true) uid=$(id -u) gid=$(id -g) HOME=${HOME:-}"
log "Env: WAYLAND_DISPLAY=${WAYLAND_DISPLAY} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR} DISPLAY=${DISPLAY:-}"
ls -ld "${XDG_RUNTIME_DIR}" "$HOME" "$HOME/.config" 2>/dev/null | while IFS= read -r line; do log "perm: ${line}"; done || true

# X11 socket dirs (needed for Xwayland/KWin X11)
mkdir -p /tmp/.X11-unix /tmp/.ICE-unix || true
chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true

# Start Sunshine early (doesn't require WM)
if command -v sunshine >/dev/null 2>&1; then
  if ! pgrep -x sunshine >/dev/null 2>&1; then
    log "Starting sunshine"
    sunshine >/config/sunshine.log 2>&1 &
  fi
fi

# Ensure Steam autostarts once Plasma is up
HOME="${HOME:-/config}"

set +e
mkdir -p "$HOME/.config/autostart" >/dev/null 2>&1
cat > "$HOME/.config/autostart/steam.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=steam-selkies
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Steam
Comment=Start Steam client
EOF
rc=$?
set -e

if [ $rc -ne 0 ]; then
  log "WARNING: Could not write $HOME/.config/autostart/steam.desktop (permission denied?). Continuing without it."
fi

# Optional: smoke test window (no-op unless STEAM_DEBUG_SMOKE_TEST=true)
if command -v selkies-smoke-test >/dev/null 2>&1; then
  selkies-smoke-test || true
fi

kde_log=/config/kde-plasma-xwayland.log
if ! can_write "${kde_log}"; then
  kde_log=/tmp/kde-plasma-xwayland.log
fi

if ! command -v Xwayland >/dev/null 2>&1; then
  log "ERROR: Xwayland not found in image; cannot start Plasma X11 in Wayland mode"
  exit 1
fi
if ! command -v startplasma-x11 >/dev/null 2>&1; then
  log "ERROR: startplasma-x11 not found in image"
  exit 1
fi

display_num=${SELKIES_XWAYLAND_DISPLAY_NUM:-1}
export DISPLAY=":${display_num}"

if [ ! -S "/tmp/.X11-unix/X${display_num}" ]; then
  log "Starting Xwayland on DISPLAY=${DISPLAY} (rootless on ${WAYLAND_DISPLAY})"
  # Rootless Xwayland on top of the existing Wayland compositor.
  # -terminate: exit when last client disconnects
  # -noreset: keep server alive across client restarts
  Xwayland "${DISPLAY}" -rootless -terminate -noreset -nolisten tcp >/config/xwayland.log 2>&1 &

  i=0
  while [ $i -lt 10 ]; do
    if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done
fi

if [ ! -S "/tmp/.X11-unix/X${display_num}" ]; then
  log "ERROR: Xwayland did not create /tmp/.X11-unix/X${display_num}; see /config/xwayland.log"
  exit 1
fi

log "Launching startplasma-x11 on ${DISPLAY}; logs -> ${kde_log}"

if command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- startplasma-x11 >>"${kde_log}" 2>&1
fi

if command -v dbus-launch >/dev/null 2>&1; then
  eval "$(dbus-launch --sh-syntax)"
  export DBUS_SESSION_BUS_ADDRESS
  exec startplasma-x11 >>"${kde_log}" 2>&1
fi

exec startplasma-x11 >>"${kde_log}" 2>&1
