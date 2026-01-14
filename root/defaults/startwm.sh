#!/usr/bin/env bash
set -euo pipefail

log() {
  echo "[steam-selkies][startwm] $*" || true
  echo "[steam-selkies][startwm] $*" >>/config/steam-selkies.log 2>/dev/null || true
}

ensure_log_writable() {
  mkdir -p /config >/dev/null 2>&1 || true
  touch /config/steam-selkies.log >/dev/null 2>&1 || true
  if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
    chown abc:users /config/steam-selkies.log >/dev/null 2>&1 || true
    chmod 664 /config/steam-selkies.log >/dev/null 2>&1 || true
  fi
}

exec_as_abc() {
  if [ "$(id -u)" -ne 0 ] || ! id abc >/dev/null 2>&1; then
    exec "$@"
  fi

  if command -v s6-setuidgid >/dev/null 2>&1; then
    exec s6-setuidgid abc "$@"
  fi

  exec su -s /bin/bash abc -c "$(printf '%q ' "$@")"
}

run_as_abc() {
  if [ "$(id -u)" -ne 0 ] || ! id abc >/dev/null 2>&1; then
    "$@"
    return $?
  fi

  if command -v s6-setuidgid >/dev/null 2>&1; then
    s6-setuidgid abc "$@"
    return $?
  fi

  su -s /bin/bash abc -c "$(printf '%q ' "$@")"
}

ensure_log_writable

SCRIPT_VERSION="2026-01-14-1"
log "Script version: ${SCRIPT_VERSION}"

# Prefer wrappers (e.g., ksmserver) when present.
export PATH="/usr/local/bin:${PATH}"

export HOME="${HOME:-/config}"

# X11 session hints.
export XDG_SESSION_TYPE=x11
export XDG_CURRENT_DESKTOP=KDE
export KDE_FULL_SESSION=true
export QT_QPA_PLATFORM=xcb
export GDK_BACKEND=x11
export CLUTTER_BACKEND=x11

# Low-latency defaults for remote streaming. User can override at runtime.
export KWIN_X11_NO_SYNC_TO_VBLANK="${KWIN_X11_NO_SYNC_TO_VBLANK:-1}"
export __GL_SYNC_TO_VBLANK="${__GL_SYNC_TO_VBLANK:-0}"

# Aggressive session trimming (good defaults for a gaming/streaming appliance).
# Override at runtime if you need PIM features.
export AKONADI_DISABLE="${AKONADI_DISABLE:-true}"

# KDE runtime dir: must be local/ephemeral (not /config) for Qt/libICE atomic temp+lock usage.
export XDG_RUNTIME_DIR="/tmp/.XDG"
mkdir -p "${XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true
chmod 700 "${XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true
if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
  chown abc:users "${XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true
fi

# Ensure a DISPLAY is set (Selkies X11 mode usually provides :0).
if [ -z "${DISPLAY:-}" ] && [ -S /tmp/.X11-unix/X0 ]; then
  export DISPLAY=":0"
fi

# Explicit auth files.
export XAUTHORITY="${HOME}/.Xauthority"
export ICEAUTHORITY="/tmp/.ICEauthority-abc"
rm -f "${XAUTHORITY}" "${ICEAUTHORITY}" \
  "${ICEAUTHORITY}-c" "${ICEAUTHORITY}-l" \
  "${ICEAUTHORITY}.c" "${ICEAUTHORITY}.l" >/dev/null 2>&1 || true
: >"${XAUTHORITY}" 2>/dev/null || true
: >"${ICEAUTHORITY}" 2>/dev/null || true
chmod 600 "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true
if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
  chown abc:users "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true
fi
rm -f "${HOME}/.ICEauthority" >/dev/null 2>&1 || true
ln -sf "${ICEAUTHORITY}" "${HOME}/.ICEauthority" >/dev/null 2>&1 || true

# Plasma 6 defaults to systemd --user integration. Containers typically do not run systemd.
export PLASMA_USE_SYSTEMD=0

# Prefer an X11 window manager (avoids any attempt to pivot to Wayland).
if command -v kwin_x11 >/dev/null 2>&1; then
  KDEWM_BIN="$(command -v kwin_x11)"
  export KDEWM="${KDEWM_BIN}"
fi

log "Running as: $(id -un 2>/dev/null || true) uid=$(id -u) gid=$(id -g) HOME=${HOME}"
log "Env: DISPLAY=${DISPLAY:-} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR} XAUTHORITY=${XAUTHORITY} ICEAUTHORITY=${ICEAUTHORITY}"

apply_kde_perf_tweaks() {
  # Defaults chosen for smooth remote GUI: fewer effects/animations, less background indexing.
  local enable_tweaks="${STEAM_KDE_PERF_TWEAKS:-true}"
  [ "${enable_tweaks}" = "true" ] || return 0

  mkdir -p "${HOME}/.config" "${HOME}/.local/share" >/dev/null 2>&1 || true

  # Only do the expensive bits once per config volume.
  local marker="${HOME}/.config/steam-selkies.x11-perf-tuned"
  if [ -e "${marker}" ] && [ "${STEAM_KDE_PERF_TWEAKS_FORCE:-false}" != "true" ]; then
    log "Perf tweaks: already applied (${marker})"
    return 0
  fi

  log "Perf tweaks: applying KDE/Plasma settings"

  local anim_factor="${STEAM_KDE_ANIMATION_FACTOR:-0}"
  if command -v kwriteconfig6 >/dev/null 2>&1; then
    run_as_abc kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor "${anim_factor}" >/dev/null 2>&1 || true

    if [ "${STEAM_KDE_DISABLE_COMPOSITING:-true}" = "true" ]; then
      run_as_abc kwriteconfig6 --file kwinrc --group Compositing --key Enabled false >/dev/null 2>&1 || true
    fi

    # Even with compositing disabled, write effect disables so if compositing gets enabled later
    # (e.g., user toggles it), we stay in a low-overhead configuration.
    if [ "${STEAM_KDE_DISABLE_EFFECTS:-true}" = "true" ]; then
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key contrastEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key translucencyEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key slideEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key wobblywindowsEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key zoomEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key magiclampEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key presentwindowsEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key desktopgridEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key windowviewEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key diminactiveEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kwinrc --group Plugins --key minimizeanimationEnabled false >/dev/null 2>&1 || true
    fi

    # Avoid unexpected black/locked screen in a streamed session.
    if [ "${STEAM_KDE_DISABLE_SCREENLOCK:-true}" = "true" ]; then
      run_as_abc kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig6 --file kscreenlockerrc --group Daemon --key Timeout 0 >/dev/null 2>&1 || true
    fi
  elif command -v kwriteconfig5 >/dev/null 2>&1; then
    run_as_abc kwriteconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor "${anim_factor}" >/dev/null 2>&1 || true

    if [ "${STEAM_KDE_DISABLE_COMPOSITING:-true}" = "true" ]; then
      run_as_abc kwriteconfig5 --file kwinrc --group Compositing --key Enabled false >/dev/null 2>&1 || true
    fi

    if [ "${STEAM_KDE_DISABLE_EFFECTS:-true}" = "true" ]; then
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key blurEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key contrastEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key translucencyEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key slideEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key wobblywindowsEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key zoomEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key magiclampEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key presentwindowsEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key desktopgridEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key windowviewEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key diminactiveEnabled false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kwinrc --group Plugins --key minimizeanimationEnabled false >/dev/null 2>&1 || true
    fi

    if [ "${STEAM_KDE_DISABLE_SCREENLOCK:-true}" = "true" ]; then
      run_as_abc kwriteconfig5 --file kscreenlockerrc --group Daemon --key Autolock false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kscreenlockerrc --group Daemon --key LockOnResume false >/dev/null 2>&1 || true
      run_as_abc kwriteconfig5 --file kscreenlockerrc --group Daemon --key Timeout 0 >/dev/null 2>&1 || true
    fi
  else
    log "Perf tweaks: kwriteconfig not found; skipping KDE settings"
  fi

  # Disable file indexing to reduce background CPU/disk churn.
  if [ "${STEAM_KDE_DISABLE_BALOO:-true}" = "true" ]; then
    if command -v balooctl6 >/dev/null 2>&1; then
      run_as_abc balooctl6 disable >/dev/null 2>&1 || true
    elif command -v balooctl >/dev/null 2>&1; then
      run_as_abc balooctl disable >/dev/null 2>&1 || true
    fi
  fi

  run_as_abc bash -lc "date -Is 2>/dev/null || date" >"${marker}" 2>/dev/null || true
}

# Optional: smoke test (no-op unless STEAM_DEBUG_SMOKE_TEST=true)
if [ "${STEAM_DEBUG_SMOKE_TEST:-}" = "true" ] && command -v selkies-smoke-test >/dev/null 2>&1; then
  selkies-smoke-test || true
fi

# Avoid repeated attempts if something respawns this script.
if [ -f /tmp/steam-selkies-kde-started ]; then
  log "KDE launch already attempted; sleeping"
  sleep 3600
  exit 0
fi
: >/tmp/steam-selkies-kde-started 2>/dev/null || true

kde_log=/config/kde-plasma-x11.log
: >"${kde_log}" 2>/dev/null || true
echo "[steam-selkies][kde-log] boot $(date -Is 2>/dev/null || date)" >>"${kde_log}" 2>/dev/null || true

log "Launching startplasma-x11; logs -> ${kde_log}"

apply_kde_perf_tweaks || true

umask 022

if command -v dbus-run-session >/dev/null 2>&1; then
  exec_as_abc dbus-run-session -- startplasma-x11 >>"${kde_log}" 2>&1
fi

if command -v dbus-launch >/dev/null 2>&1; then
  exec_as_abc bash -lc 'eval "$(dbus-launch --sh-syntax)"; export DBUS_SESSION_BUS_ADDRESS; exec startplasma-x11' >>"${kde_log}" 2>&1
fi

exec_as_abc startplasma-x11 >>"${kde_log}" 2>&1
