#!/usr/bin/env bash
set -euo pipefail

# This script is used by linuxserver/baseimage-selkies when PIXELFLUX_WAYLAND=true.
# It replaces the default wlroots compositor (e.g. labwc) with KDE Plasma Wayland.

log() {
  echo "[steam-selkies][startwm_wayland] $*" | tee -a /config/steam-selkies.log >/dev/null 2>&1 || true
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
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}" || true

# Start Sunshine early (doesn't require WM)
if command -v sunshine >/dev/null 2>&1; then
  if ! pgrep -x sunshine >/dev/null 2>&1; then
    log "Starting sunshine"
    sunshine >/config/sunshine.log 2>&1 &
  fi
fi

# Ensure Steam autostarts once Plasma is up
mkdir -p "$HOME/.config/autostart"
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

# Optional: smoke test window (no-op unless STEAM_DEBUG_SMOKE_TEST=true)
if command -v selkies-smoke-test >/dev/null 2>&1; then
  selkies-smoke-test || true
fi

kde_log=/config/kde-plasma-wayland.log
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
