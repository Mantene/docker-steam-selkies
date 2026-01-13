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

# X11/ICE socket dirs: ideally root-owned, but some base setups clear /tmp.
# Create them if missing so Xwayland can start; log ownership for debugging.
mkdir -p /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true
chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true

tmp_x11_owner="$(stat -c %U /tmp/.X11-unix 2>/dev/null || true)"
tmp_ice_owner="$(stat -c %U /tmp/.ICE-unix 2>/dev/null || true)"
if [ "${tmp_x11_owner}" != "root" ] || [ "${tmp_ice_owner}" != "root" ]; then
  log "WARNING: /tmp socket dirs not root-owned (X11=${tmp_x11_owner} ICE=${tmp_ice_owner}); warnings are expected"
fi

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

display_num=${SELKIES_XWAYLAND_DISPLAY_NUM:-}
if [ -n "${display_num}" ]; then
  export DISPLAY=":${display_num}"
else
  export DISPLAY=""
fi

# Explicit auth files (prevents Plasma tools from failing to connect/auth to the Xwayland display)
export XAUTHORITY="$HOME/.Xauthority"
export ICEAUTHORITY="$HOME/.ICEauthority"
rm -f "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true
touch "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true
chmod 600 "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true

# Force an X11 window manager. Plasma can otherwise try kwin_wayland_wrapper --xwayland,
# which still requires DRM/KMS and fails in many container setups.
if command -v kwin_x11 >/dev/null 2>&1; then
  KDEWM_BIN="$(command -v kwin_x11)"
  export KDEWM="${KDEWM_BIN}"
  log "Set KDEWM=${KDEWM}"
fi

if [ -n "${display_num}" ]; then
  if [ ! -S "/tmp/.X11-unix/X${display_num}" ]; then
    log "Starting Xwayland on DISPLAY=${DISPLAY} (rootless on ${WAYLAND_DISPLAY})"
    Xwayland "${DISPLAY}" -rootless -noreset -nolisten tcp -auth "${XAUTHORITY}" >/config/xwayland.log 2>&1 &
  fi

  i=0
  while [ $i -lt 30 ]; do
    if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  if [ ! -S "/tmp/.X11-unix/X${display_num}" ]; then
    log "ERROR: Xwayland did not create /tmp/.X11-unix/X${display_num}; see /config/xwayland.log"
    exit 1
  fi
else
  log "Starting Xwayland with -displayfd (auto-pick display) on ${WAYLAND_DISPLAY}"
  dispfile="$(mktemp -p /tmp selkies-xwayland-display.XXXXXX)"
  rm -f "${dispfile}" >/dev/null 2>&1 || true
  : >"${dispfile}" 2>/dev/null || true

  # Start Xwayland and have it write the chosen display number to fd 3.
  exec 3>"${dispfile}"
  Xwayland -rootless -noreset -nolisten tcp -auth "${XAUTHORITY}" -displayfd 3 >/config/xwayland.log 2>&1 &
  exec 3>&-

  i=0
  while [ $i -lt 10 ]; do
    display_num="$(cat "${dispfile}" 2>/dev/null | tr -d '[:space:]' || true)"
    if [ -n "${display_num}" ]; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  if [ -z "${display_num}" ]; then
    log "ERROR: Xwayland did not report a display number via -displayfd; see /config/xwayland.log"
    exit 1
  fi

  export DISPLAY=":${display_num}"

  i=0
  while [ $i -lt 30 ]; do
    if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done

  if [ ! -S "/tmp/.X11-unix/X${display_num}" ]; then
    log "ERROR: Xwayland did not create /tmp/.X11-unix/X${display_num}; see /config/xwayland.log"
    exit 1
  fi
fi

log "Launching startplasma-x11 on ${DISPLAY}; logs -> ${kde_log}"

# Ensure Plasma actually behaves as an X11 session.
# We only needed WAYLAND_DISPLAY to start rootless Xwayland; keeping it set can
# cause some components to pick Wayland backends and try kwin_wayland_wrapper.
unset WAYLAND_DISPLAY
export XDG_SESSION_TYPE=x11
export QT_QPA_PLATFORM=xcb
export GDK_BACKEND=x11
export CLUTTER_BACKEND=x11

if command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- startplasma-x11 >>"${kde_log}" 2>&1
fi

if command -v dbus-launch >/dev/null 2>&1; then
  eval "$(dbus-launch --sh-syntax)"
  export DBUS_SESSION_BUS_ADDRESS
  exec startplasma-x11 >>"${kde_log}" 2>&1
fi

exec startplasma-x11 >>"${kde_log}" 2>&1
