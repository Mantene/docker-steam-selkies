#!/usr/bin/env bash
set -euo pipefail

# This script is used by linuxserver/baseimage-selkies when PIXELFLUX_WAYLAND=true.
# It replaces the default wlroots compositor (e.g. labwc) with KDE Plasma Wayland.

log() {
  echo "[steam-selkies][startwm_wayland] $*" | tee -a /config/steam-selkies.log >/dev/null 2>&1 || true
}

can_write() {
  local p="$1"
  ( : >>"$p" ) >/dev/null 2>&1
}

# Basic session hints
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=KDE
export KDE_FULL_SESSION=true
export QT_QPA_PLATFORM=wayland

# Selkies conventions: compositor socket is typically wayland-1
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

# Runtime dir: base images commonly use /config/.XDG
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/config/.XDG}
mkdir -p "${XDG_RUNTIME_DIR}" || true
chmod 700 "${XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true

log "Running as: $(id -un 2>/dev/null || true) uid=$(id -u) gid=$(id -g) HOME=${HOME:-}"
log "Dirs: XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}"
ls -ld "${XDG_RUNTIME_DIR}" "$HOME" "$HOME/.config" 2>/dev/null | while IFS= read -r line; do log "perm: ${line}"; done || true

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

kde_log=/config/kde-plasma-wayland.log
if ! can_write "${kde_log}"; then
  kde_log=/tmp/kde-plasma-wayland.log
fi
log "Launching startplasma-wayland (WAYLAND_DISPLAY=${WAYLAND_DISPLAY} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}); logs -> ${kde_log}"

# startplasma-wayland launches kwin_wayland itself as the compositor.
if command -v dbus-run-session >/dev/null 2>&1; then
  exec dbus-run-session -- startplasma-wayland >>"${kde_log}" 2>&1
fi

if command -v dbus-launch >/dev/null 2>&1; then
  eval "$(dbus-launch --sh-syntax)"
  export DBUS_SESSION_BUS_ADDRESS
  exec startplasma-wayland >>"${kde_log}" 2>&1
fi

exec startplasma-wayland >>"${kde_log}" 2>&1
