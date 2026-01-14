#!/usr/bin/env bash
set -euo pipefail

# This script is used by linuxserver/baseimage-selkies when PIXELFLUX_WAYLAND=true.
# The base image provides a Wayland compositor (labwc) and a Wayland socket.
# Running Plasma Wayland as a second compositor often fails in containers due to
# DRM/KMS access requirements; instead we run Plasma X11 on Xwayland.

log() {
  # Log both to stdout (container logs) and to the persisted /config log.
  echo "[steam-selkies][startwm_wayland] $*" || true
  echo "[steam-selkies][startwm_wayland] $*" >>/config/steam-selkies.log 2>/dev/null || true
}

ensure_log_writable() {
  mkdir -p /config >/dev/null 2>&1 || true
  touch /config/steam-selkies.log >/dev/null 2>&1 || true
  if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
    chown abc:users /config/steam-selkies.log >/dev/null 2>&1 || true
    chmod 664 /config/steam-selkies.log >/dev/null 2>&1 || true
  fi
}

abc_env_args() {
  # Build a stable set of env vars so user-switch tools can't silently reset HOME/auth paths.
  # Intentionally do not include WAYLAND_DISPLAY here; it may be unset for Plasma X11.
  local home="${HOME:-/config}"
  # XDG_RUNTIME_DIR should be on a local/ephemeral filesystem; keeping it on /config
  # (host bind mounts / FUSE) can break atomic temp/lock behavior used by Qt/libICE.
  local runtime="${KDE_XDG_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp/.XDG}}"
  if printf '%s' "${runtime}" | grep -q '^/config/'; then runtime="/tmp/.XDG"; fi
  local tmp="${TMPDIR:-/config/tmp}"
  local xauth="${XAUTHORITY:-${home}/.Xauthority}"
  local iceauth="${ICEAUTHORITY:-${home}/.ICEauthority}"

  ABC_ENV=(
    env
    "HOME=${home}"
    "USER=abc"
    "LOGNAME=abc"
    "XDG_RUNTIME_DIR=${runtime}"
    "DISPLAY=${DISPLAY:-}"
    "XAUTHORITY=${xauth}"
    "ICEAUTHORITY=${iceauth}"
    "TMPDIR=${tmp}"
    "PATH=${PATH}"
  )
}

run_as_abc_env() {
  # Usage: run_as_abc_env VAR=... VAR=... -- cmd args...
  local -a envs
  envs=()
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--" ]; then
      shift
      break
    fi
    envs+=("$1")
    shift
  done

  # If we're already running as the target user (or 'abc' doesn't exist), just apply
  # the env vars and run the command. Important: do NOT pass the `--` separator to `env`.
  if [ "$(id -u)" -ne 0 ] || ! id abc >/dev/null 2>&1; then
    env "${envs[@]}" "$@"
    return $?
  fi

  if command -v s6-setuidgid >/dev/null 2>&1; then
    s6-setuidgid abc env "${envs[@]}" "$@"
    return $?
  fi
  if command -v runuser >/dev/null 2>&1; then
    runuser -u abc --preserve-environment -- env "${envs[@]}" "$@"
    return $?
  fi

  su -m -s /bin/bash abc -c "env $(printf '%q ' "${envs[@]}") $(printf '%q ' "$@")"
}

run_as_abc() {
  if [ "$(id -u)" -ne 0 ] || ! id abc >/dev/null 2>&1; then
    "$@"
    return $?
  fi

  if command -v s6-setuidgid >/dev/null 2>&1; then
    abc_env_args
    s6-setuidgid abc "${ABC_ENV[@]}" "$@"
    return $?
  fi
  if command -v runuser >/dev/null 2>&1; then
    abc_env_args
    runuser -u abc --preserve-environment -- "${ABC_ENV[@]}" "$@"
    return $?
  fi

  # Fallback
  abc_env_args
  su -m -s /bin/bash abc -c "$(printf '%q ' "${ABC_ENV[@]}" "$@")"
}

exec_as_abc() {
  if [ "$(id -u)" -ne 0 ] || ! id abc >/dev/null 2>&1; then
    exec "$@"
  fi

  if command -v s6-setuidgid >/dev/null 2>&1; then
    abc_env_args
    exec s6-setuidgid abc "${ABC_ENV[@]}" "$@"
  fi
  if command -v runuser >/dev/null 2>&1; then
    abc_env_args
    exec runuser -u abc --preserve-environment -- "${ABC_ENV[@]}" "$@"
  fi

  abc_env_args
  exec su -m -s /bin/bash abc -c "$(printf '%q ' "${ABC_ENV[@]}" "$@")"
}

can_write() {
  local p="$1"
  ( : >>"$p" ) >/dev/null 2>&1
}

# Session hints
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=KDE
export KDE_FULL_SESSION=true

# Ensure our debug/compat wrappers (e.g., /usr/local/bin/xrdb) are preferred.
export PATH="/usr/local/bin:${PATH}"

ensure_log_writable

# Bump this when changing startup semantics so logs can confirm which script is running.
SCRIPT_VERSION="2026-01-14-1"
log "Script version: ${SCRIPT_VERSION}"

log "Smoke test: STEAM_DEBUG_SMOKE_TEST=${STEAM_DEBUG_SMOKE_TEST:-} (set to 'true' to force an always-changing xterm window)"

# NVIDIA proprietary drivers require nvidia_drm KMS modesetting for wlroots/GBM paths.
# Without it, PIXELFLUX_WAYLAND sessions often initialize but stream black / capture loop stops.
nvidia_modeset=""
if [ -r /sys/module/nvidia_drm/parameters/modeset ]; then
  nvidia_modeset="$(cat /sys/module/nvidia_drm/parameters/modeset 2>/dev/null | tr -d '\n' || true)"
  log "Host kernel: nvidia_drm.modeset=${nvidia_modeset:-unknown} (/sys/module)"
else
  # Some container runtimes hide /sys/module/*; try to infer via the active DRM device.
  if [ -r /proc/modules ] && grep -q '^nvidia_drm ' /proc/modules 2>/dev/null; then
    log "Host kernel: nvidia_drm is loaded but /sys/module/nvidia_drm/parameters/modeset is not readable in this container"
  else
    log "Host kernel: nvidia_drm module not detected (/sys/module/nvidia_drm missing)"
  fi

  for card in /sys/class/drm/card*/device/driver/module/parameters/modeset; do
    [ -e "${card}" ] || continue
    v="$(cat "${card}" 2>/dev/null | tr -d '\n' || true)"
    if [ -n "${v}" ]; then
      log "Host kernel: nvidia_drm.modeset=${v} (${card})"
      nvidia_modeset="${v}"
      break
    fi
  done

  if [ -r /proc/driver/nvidia/version ]; then
    ver="$(head -n 1 /proc/driver/nvidia/version 2>/dev/null || true)"
    [ -n "${ver}" ] && log "Host kernel: ${ver}"
  fi
fi

if [ "${nvidia_modeset}" = "N" ] || [ "${nvidia_modeset}" = "0" ]; then
  log "WARNING: NVIDIA KMS modeset appears disabled; Wayland capture is likely to fail (black screen)."
  log "WARNING: Fix: enable nvidia_drm.modeset=1 on the host, or run with PIXELFLUX_WAYLAND=false (X11 mode)."
fi

if [ -d /dev/dri ]; then
  ls -l /dev/dri 2>/dev/null | while IFS= read -r line; do log "dri: ${line}"; done || true
fi

# Xwayland must connect to the *compositor's* Wayland socket.
# Some setups expose multiple wayland-* sockets; pick one that is actually connectable.
wayland_can_connect() {
  local sock_path="$1"
  [ -S "${sock_path}" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "${sock_path}" <<'PY'
import socket, sys
path = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect(path)
except OSError as e:
    # Print errno info for callers to log.
    print(f"ERRNO={e.errno} {e.strerror}")
    sys.exit(1)
finally:
    try:
        s.close()
    except Exception:
        pass
sys.exit(0)
PY
    return $?
  fi

  # Fallback: attempt a basic connect via socat if present.
  if command -v socat >/dev/null 2>&1; then
    socat -T 1 - "UNIX-CONNECT:${sock_path}" </dev/null >/dev/null 2>&1
    return $?
  fi
  return 0
}

pick_wayland_socket() {
  local requested_display="${WAYLAND_DISPLAY:-}"
  local orig_runtime="${XDG_RUNTIME_DIR:-}"
  local uid_cand
  uid_cand="$(id -u abc 2>/dev/null || echo 99)"

  local -a runtime_dirs
  runtime_dirs=("${orig_runtime}" "/config/.XDG" "/run/user/${uid_cand}")

  for rt in "${runtime_dirs[@]}"; do
    [ -n "${rt}" ] || continue
    [ -d "${rt}" ] || continue

    # First try the explicitly requested WAYLAND_DISPLAY (if any).
    if [ -n "${requested_display}" ] && [ -S "${rt}/${requested_display}" ]; then
      out="$(wayland_can_connect "${rt}/${requested_display}" 2>&1)"
      if [ $? -eq 0 ]; then
        echo "${rt}|${requested_display}"
        return 0
      fi
      log "WARNING: Wayland socket exists but is not connectable: ${rt}/${requested_display} (${out:-unknown error})"
    fi

    # Otherwise probe any wayland-* sockets that exist.
    for sock in "${rt}"/wayland-*; do
      [ -S "${sock}" ] || continue
      sock_name="$(basename "${sock}")"
      out="$(wayland_can_connect "${sock}" 2>&1)"
      if [ $? -eq 0 ]; then
        echo "${rt}|${sock_name}"
        return 0
      fi
      log "WARNING: Wayland socket not connectable: ${sock} (${out:-unknown error})"
    done
  done

  return 1
}

SELKIES_XDG_RUNTIME_DIR=""
SELKIES_WAYLAND_DISPLAY=""
if picked="$(pick_wayland_socket 2>/dev/null)"; then
  SELKIES_XDG_RUNTIME_DIR="${picked%%|*}"
  SELKIES_WAYLAND_DISPLAY="${picked##*|}"
else
  # Fall back to prior behavior: default to wayland-1 under /config/.XDG.
  SELKIES_WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
  ORIG_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
  SELKIES_XDG_RUNTIME_DIR="${ORIG_XDG_RUNTIME_DIR:-/config/.XDG}"
  log "WARNING: Could not find a connectable Wayland socket; falling back to ${SELKIES_XDG_RUNTIME_DIR}/${SELKIES_WAYLAND_DISPLAY}"
fi

export WAYLAND_DISPLAY="${SELKIES_WAYLAND_DISPLAY}"
log "Selkies runtime: WAYLAND_DISPLAY=${SELKIES_WAYLAND_DISPLAY} XDG_RUNTIME_DIR=${SELKIES_XDG_RUNTIME_DIR}"

# The compositor may create the runtime dir/socket slightly after this script starts.
# Wait briefly for the socket to appear to avoid a first-attempt Xwayland failure.
selkies_wayland_socket="${SELKIES_XDG_RUNTIME_DIR}/${SELKIES_WAYLAND_DISPLAY}"
i=0
while [ $i -lt 50 ]; do
  if [ -S "${selkies_wayland_socket}" ]; then
    break
  fi
  i=$((i + 1))
  sleep 0.1
done
if [ -S "${selkies_wayland_socket}" ]; then
  log "Selkies socket: present at ${selkies_wayland_socket}"
  # Give the compositor a moment to become connectable.
  # (Socket existence is not enough; connection may still be refused early in boot.)
  # Default to 20s; can be tuned via STEAM_WAYLAND_CONNECT_WAIT_SECS.
  wait_secs="${STEAM_WAYLAND_CONNECT_WAIT_SECS:-20}"
  max_tries=$((wait_secs * 10))
  j=0
  while [ $j -lt ${max_tries} ]; do
    out="$(wayland_can_connect "${selkies_wayland_socket}" 2>&1)"
    if [ $? -eq 0 ]; then
      break
    fi
    j=$((j + 1))
    sleep 0.1
  done
  if [ $j -ge ${max_tries} ]; then
    log "ERROR: Wayland socket exists but is not connectable after ${wait_secs}s: ${selkies_wayland_socket} (${out:-unknown error})"
    log "Refusing to start Xwayland/Plasma against a non-ready compositor (prevents black screen / dead DISPLAY)."
    exit 1
  fi
else
  log "WARNING: Selkies socket not present at ${selkies_wayland_socket} (continuing; Xwayland may fail)"
fi

# KDE runtime dir: must be local/ephemeral (not /config) for Qt/libICE atomic temp+lock usage.
export KDE_XDG_RUNTIME_DIR=/tmp/.XDG
mkdir -p "${KDE_XDG_RUNTIME_DIR}" || true
chmod 700 "${KDE_XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true

if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
  chown abc:users "${KDE_XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true
  chmod 700 "${KDE_XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true
fi

# Use the KDE runtime dir for the rest of the session, but keep SELKIES_* for Xwayland.
export XDG_RUNTIME_DIR="${KDE_XDG_RUNTIME_DIR}"

export HOME="${HOME:-/config}"
log "Running as: $(id -un 2>/dev/null || true) uid=$(id -u) gid=$(id -g) HOME=${HOME:-}"
log "Env: WAYLAND_DISPLAY=${WAYLAND_DISPLAY} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR} DISPLAY=${DISPLAY:-}"

# Ensure common per-user dirs exist (KDE expects these); avoid root-owned files under /config.
mkdir -p "$HOME/.config" "$HOME/.local/share" "$HOME/.cache" >/dev/null 2>&1 || true
if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
  chown -R abc:users "$HOME/.config" "$HOME/.local" "$HOME/.cache" >/dev/null 2>&1 || true
fi

ls -ld "${SELKIES_XDG_RUNTIME_DIR}" "${XDG_RUNTIME_DIR}" "$HOME" "$HOME/.config" 2>/dev/null | while IFS= read -r line; do log "perm: ${line}"; done || true

# Prefer a stable temp directory for KDE tooling.
export TMPDIR="${TMPDIR:-/config/tmp}"
mkdir -p "${TMPDIR}" >/dev/null 2>&1 || true
chmod 1777 "${TMPDIR}" >/dev/null 2>&1 || true

if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
  # Prefer a simple per-user tmp directory to avoid cross-UID temp file issues.
  chown abc:users "${TMPDIR}" >/dev/null 2>&1 || true
  chmod 700 "${TMPDIR}" >/dev/null 2>&1 || true
fi

# X11/ICE socket dirs: Xwayland and KDE session pieces behave best when these
# are root-owned 1777. Try to enforce that (root via sudo if available).
fix_tmp_socket_dirs() {
  mkdir -p /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true
  chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true

  if [ "$(id -u)" -eq 0 ]; then
    rm -f /tmp/.X11-unix/X* /tmp/.ICE-unix/* >/dev/null 2>&1 || true
    chown root:root /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true
    chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix >/dev/null 2>&1 || true
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo -n sh -c 'mkdir -p /tmp/.X11-unix /tmp/.ICE-unix && rm -f /tmp/.X11-unix/X* /tmp/.ICE-unix/* && chown root:root /tmp/.X11-unix /tmp/.ICE-unix && chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix' >/dev/null 2>&1 || true
  fi
}

fix_tmp_socket_dirs

# Ensure /tmp itself has standard permissions (some container setups tighten this).
chmod 1777 /tmp >/dev/null 2>&1 || true
if [ "$(id -u)" -eq 0 ]; then
  chown root:root /tmp >/dev/null 2>&1 || true
fi

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

set +e
run_as_abc mkdir -p "$HOME/.config/autostart" >/dev/null 2>&1
run_as_abc_env "HOME=${HOME}" "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" -- bash -lc 'cat > "$HOME/.config/autostart/steam.desktop" <<EOF
[Desktop Entry]
Type=Application
Exec=steam-selkies
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Steam
Comment=Start Steam client
EOF
'
rc=$?
set -e

if [ $rc -ne 0 ]; then
  log "WARNING: Could not write $HOME/.config/autostart/steam.desktop (permission denied?). Continuing without it."
fi



kde_log=/config/kde-plasma-xwayland.log
if ! can_write "${kde_log}"; then
  kde_log=/tmp/kde-plasma-xwayland.log
fi

# Start each boot with a fresh KDE log to avoid chasing stale errors.
: >"${kde_log}" 2>/dev/null || true
echo "[steam-selkies][kde-log] boot $(date -Is 2>/dev/null || date)" >>"${kde_log}" 2>/dev/null || true

if ! command -v Xwayland >/dev/null 2>&1; then
  log "ERROR: Xwayland not found in image; cannot start Plasma X11 in Wayland mode"
  exit 1
fi
if ! command -v startplasma-x11 >/dev/null 2>&1; then
  log "ERROR: startplasma-x11 not found in image"
  exit 1
fi

display_num=${SELKIES_XWAYLAND_DISPLAY_NUM:-}

# Some baseimage-selkies variants export DISPLAY (often :1) before running this script.
# Prefer that DISPLAY number first when probing/starting Xwayland.
BASE_DISPLAY_RAW="${DISPLAY:-}"
export DISPLAY=""
BASE_DISPLAY_NUM=""
if printf '%s' "${BASE_DISPLAY_RAW}" | grep -Eq '^:[0-9]+$'; then
  BASE_DISPLAY_NUM="${BASE_DISPLAY_RAW#:}"
fi

# Explicit auth files (prevents Plasma tools from failing to connect/auth to the Xwayland display)
export XAUTHORITY="$HOME/.Xauthority"
# IMPORTANT: put ICEAUTHORITY on a local filesystem (e.g., /tmp). Some hosts (notably Unraid
# user shares) can be FUSE-backed and may not support the link/lock semantics libICE uses.
export ICEAUTHORITY="/tmp/.ICEauthority-abc"
rm -f "${XAUTHORITY}" "${ICEAUTHORITY}" \
  "${ICEAUTHORITY}-c" "${ICEAUTHORITY}-l" \
  "${ICEAUTHORITY}.c" "${ICEAUTHORITY}.l" >/dev/null 2>&1 || true
touch "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true
chmod 600 "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true

# Some components ignore ICEAUTHORITY and hardcode ~/.ICEauthority.
# Point that at the local /tmp authority file to avoid FUSE/locking issues.
rm -f "$HOME/.ICEauthority" >/dev/null 2>&1 || true
ln -sf "${ICEAUTHORITY}" "$HOME/.ICEauthority" >/dev/null 2>&1 || true

if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
  chown abc:users "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true
fi

stat -c 'auth: %a %U:%G %n' "${XAUTHORITY}" "${ICEAUTHORITY}" 2>/dev/null | while IFS= read -r line; do log "${line}"; done || true

# Force an X11 window manager. Plasma can otherwise try kwin_wayland_wrapper --xwayland,
# which still requires DRM/KMS and fails in many container setups.
if command -v kwin_x11 >/dev/null 2>&1; then
  KDEWM_BIN="$(command -v kwin_x11)"
  export KDEWM="${KDEWM_BIN}"
  log "Set KDEWM=${KDEWM}"
fi

# Plasma 6 defaults to systemd --user integration. In containers without systemd,
# this causes repeated org.freedesktop.systemd1 activation failures and can break
# session startup. Force the non-systemd path.
export PLASMA_USE_SYSTEMD=0

is_x11_responsive() {
  # Require more than just a socket file; stale sockets happen when Xwayland dies early.
  local disp="$1"
  [ -n "${disp}" ] || return 1
  if command -v xdpyinfo >/dev/null 2>&1; then
    run_as_abc xdpyinfo -display "${disp}" >/dev/null 2>&1
    return $?
  fi
  # Best-effort fallback (less reliable than xdpyinfo).
  if command -v xset >/dev/null 2>&1; then
    run_as_abc xset -display "${disp}" q >/dev/null 2>&1
    return $?
  fi
  return 0
}

rm_stale_x11_socket() {
  local n="$1"
  [ -n "${n}" ] || return 0
  rm -f "/tmp/.X11-unix/X${n}" >/dev/null 2>&1 || true
}

# If the base compositor already started Xwayland, reuse it.
# Prefer the base-provided DISPLAY number (commonly :1) when present.
probe_order=()
if [ -n "${BASE_DISPLAY_NUM}" ]; then probe_order+=("${BASE_DISPLAY_NUM}"); fi
probe_order+=(0 1 2 3 4 5 6 7 8 9)

for n in "${probe_order[@]}"; do
  if [ -S "/tmp/.X11-unix/X${n}" ]; then
    if is_x11_responsive ":${n}"; then
      display_num="$n"
      break
    fi
    log "WARNING: Found X socket /tmp/.X11-unix/X${n} but X is not responsive; removing stale socket"
    rm_stale_x11_socket "${n}"
  fi
done

if [ -z "${display_num}" ]; then
  # Try to start our own rootless Xwayland on a free display.
  for n in "${probe_order[@]}"; do
    if [ -S "/tmp/.X11-unix/X${n}" ]; then
      continue
    fi
    display_num="$n"
    export DISPLAY=":${display_num}"

    # Populate the Xauthority file with a cookie before starting Xwayland.
    if command -v xauth >/dev/null 2>&1; then
      cookie="$( (command -v mcookie >/dev/null 2>&1 && mcookie) || (openssl rand -hex 16 2>/dev/null) || (dd if=/dev/urandom bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n') )"
      if [ -n "${cookie}" ]; then
        xauth -f "${XAUTHORITY}" remove "${DISPLAY}" >/dev/null 2>&1 || true
        xauth -f "${XAUTHORITY}" add "${DISPLAY}" MIT-MAGIC-COOKIE-1 "${cookie}" >/dev/null 2>&1 || true
        xauth -f "${XAUTHORITY}" add "unix${DISPLAY}" MIT-MAGIC-COOKIE-1 "${cookie}" >/dev/null 2>&1 || true
      fi
    else
      log "WARNING: xauth not found; X11 authentication may fail (install xauth)"
    fi

    # Preserve logs per DISPLAY attempt; keep /config/xwayland.log pointing to the latest.
    xwlog="/config/xwayland.${display_num}.log"
    ln -sf "$(basename "${xwlog}")" /config/xwayland.log >/dev/null 2>&1 || true
    {
      echo "[steam-selkies][xwayland] boot $(date -Is 2>/dev/null || date) DISPLAY=${DISPLAY}"
      echo "[steam-selkies][xwayland] SELKIES_WAYLAND_DISPLAY=${SELKIES_WAYLAND_DISPLAY} SELKIES_XDG_RUNTIME_DIR=${SELKIES_XDG_RUNTIME_DIR}"
    } >>"${xwlog}" 2>/dev/null || true

    log "Starting Xwayland on DISPLAY=${DISPLAY} (rootless on ${SELKIES_WAYLAND_DISPLAY})"
    log "Xwayland log: ${xwlog} (symlink /config/xwayland.log -> ${xwlog})"
    # -ac disables access control; inside a container this avoids brittle Xauthority issues.
    start_xwayland() {
      run_as_abc_env \
        "HOME=${HOME}" "USER=abc" "LOGNAME=abc" \
        "XDG_RUNTIME_DIR=${SELKIES_XDG_RUNTIME_DIR}" "WAYLAND_DISPLAY=${SELKIES_WAYLAND_DISPLAY}" \
        "DISPLAY=${DISPLAY}" "XAUTHORITY=${XAUTHORITY}" "ICEAUTHORITY=${ICEAUTHORITY}" "TMPDIR=${TMPDIR}" "PATH=${PATH}" \
        -- Xwayland "${DISPLAY}" -rootless -noreset -nolisten tcp -ac -auth "${XAUTHORITY}" >>"${xwlog}" 2>&1 &
      xwpid=$!
    }

    xwpid=""
    xw_retried=0
    start_xwayland

    i=0
    while [ $i -lt 30 ]; do
      if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
        break
      fi
      if ! kill -0 "${xwpid}" >/dev/null 2>&1; then
        log "ERROR: Xwayland exited early (pid=${xwpid}); see ${xwlog}"
        # Common transient failure: compositor isn't ready yet.
        if [ "${xw_retried}" -eq 0 ] && tail -n 50 "${xwlog}" 2>/dev/null | grep -q "could not connect to wayland server"; then
          log "Retrying Xwayland once on ${DISPLAY} after brief delay (Wayland not ready?)"
          sleep 0.5
          xw_retried=1
          start_xwayland
          # reset wait loop for the retry
          i=0
          continue
        fi
        break
      fi
      sleep 1
      i=$((i + 1))
    done

    if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
      # Socket exists; now require that the X server is accepting connections.
      if is_x11_responsive "${DISPLAY}"; then
        break
      fi
      log "WARNING: X socket exists at /tmp/.X11-unix/X${display_num} but X is not responsive; cleaning up and trying next display"
      kill "${xwpid}" >/dev/null 2>&1 || true
      rm_stale_x11_socket "${display_num}"
    fi
    # Try next display number.
    display_num=""
    export DISPLAY=""
  done
else
  export DISPLAY=":${display_num}"
  log "Reusing existing Xwayland socket at ${DISPLAY}"
fi

if [ -z "${display_num}" ] || [ ! -S "/tmp/.X11-unix/X${display_num}" ]; then
  log "ERROR: No usable X11 socket found/created under /tmp/.X11-unix; see /config/xwayland.log"
  exit 1
fi

# Wait until the X server is accepting connections (prevents kcminit/xrdb race).
if command -v xdpyinfo >/dev/null 2>&1; then
  i=0
  while [ $i -lt 60 ]; do
    if run_as_abc xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done
  if [ $i -ge 60 ]; then
    log "ERROR: X did not become ready within 60s on ${DISPLAY}; refusing to start Plasma on a dead X server"
    tail -n 100 /config/xwayland.log 2>/dev/null | while IFS= read -r line; do log "xwayland.log: ${line}"; done || true
    exit 1
  fi
fi

# Optional: smoke test (no-op unless STEAM_DEBUG_SMOKE_TEST=true)
# Run it *after* X is confirmed responsive so it actually draws pixels.
if [ "${STEAM_DEBUG_SMOKE_TEST:-}" = "true" ]; then
  if command -v xsetroot >/dev/null 2>&1; then
    run_as_abc_env "HOME=${HOME}" "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR}" "DISPLAY=${DISPLAY}" "XAUTHORITY=${XAUTHORITY}" "ICEAUTHORITY=${ICEAUTHORITY}" -- \
      xsetroot -solid "#204060" >/dev/null 2>&1 || true
  fi
  if command -v selkies-smoke-test >/dev/null 2>&1; then
    selkies-smoke-test || true
  else
    log "WARNING: STEAM_DEBUG_SMOKE_TEST=true but selkies-smoke-test is not installed in PATH"
  fi
fi

log "Launching startplasma-x11 on ${DISPLAY}; logs -> ${kde_log}"
log "Plasma env: HOME=${HOME} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR} DISPLAY=${DISPLAY} XAUTHORITY=${XAUTHORITY} ICEAUTHORITY=${ICEAUTHORITY} TMPDIR=${TMPDIR}"

# Ensure sane default permissions for KDE-generated temp files.
umask 022

# Preflight diagnostics for the two remaining persistent failures (xrdb + ICEAuthority).
if command -v xrdb >/dev/null 2>&1; then
  if ! run_as_abc xrdb -version >/dev/null 2>&1; then
    log "WARNING: xrdb is not executable for abc; capturing diagnostics"
    ls -l /usr/bin/xrdb 2>/dev/null | while IFS= read -r line; do log "xrdb: ${line}"; done || true
    run_as_abc ls -l /usr/bin/xrdb 2>/dev/null | while IFS= read -r line; do log "xrdb(abc): ${line}"; done || true
    mount 2>/dev/null | grep -E ' on (/usr|/config|/tmp) ' | while IFS= read -r line; do log "mount: ${line}"; done || true
    if [ -r /proc/self/attr/current ]; then
      log "lsm: $(cat /proc/self/attr/current 2>/dev/null || true)"
    fi
  fi
fi

if command -v iceauth >/dev/null 2>&1; then
  if ! run_as_abc iceauth -f "${ICEAUTHORITY}" list >/dev/null 2>&1; then
    log "WARNING: iceauth cannot read ICEAUTHORITY as abc"
  fi
fi

# Ensure Plasma actually behaves as an X11 session.
# We only needed WAYLAND_DISPLAY to start rootless Xwayland; keeping it set can
# cause some components to pick Wayland backends and try kwin_wayland_wrapper.
unset WAYLAND_DISPLAY
export XDG_SESSION_TYPE=x11
export QT_QPA_PLATFORM=xcb
export GDK_BACKEND=x11
export CLUTTER_BACKEND=x11

if command -v dbus-run-session >/dev/null 2>&1; then
  exec_as_abc dbus-run-session -- startplasma-x11 >>"${kde_log}" 2>&1
fi

if command -v dbus-launch >/dev/null 2>&1; then
  # Keep fallback compatible with either root or abc execution.
  exec_as_abc bash -lc 'eval "$(dbus-launch --sh-syntax)"; export DBUS_SESSION_BUS_ADDRESS; exec startplasma-x11' >>"${kde_log}" 2>&1
fi

exec_as_abc startplasma-x11 >>"${kde_log}" 2>&1
