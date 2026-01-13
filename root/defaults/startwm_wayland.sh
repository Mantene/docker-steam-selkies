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
  local runtime="${XDG_RUNTIME_DIR:-/config/.XDG}"
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

# Selkies conventions: compositor socket is typically wayland-1
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}

# Runtime dir: base images commonly use /config/.XDG
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/config/.XDG}
mkdir -p "${XDG_RUNTIME_DIR}" || true
chmod 700 "${XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true

if [ "$(id -u)" -eq 0 ] && id abc >/dev/null 2>&1; then
  chown abc:users "${XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true
  chmod 700 "${XDG_RUNTIME_DIR}" >/dev/null 2>&1 || true
fi

export HOME="${HOME:-/config}"
log "Running as: $(id -un 2>/dev/null || true) uid=$(id -u) gid=$(id -g) HOME=${HOME:-}"
log "Env: WAYLAND_DISPLAY=${WAYLAND_DISPLAY} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR} DISPLAY=${DISPLAY:-}"
ls -ld "${XDG_RUNTIME_DIR}" "$HOME" "$HOME/.config" 2>/dev/null | while IFS= read -r line; do log "perm: ${line}"; done || true

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
export DISPLAY=""

# Explicit auth files (prevents Plasma tools from failing to connect/auth to the Xwayland display)
export XAUTHORITY="$HOME/.Xauthority"
export ICEAUTHORITY="/tmp/.ICEauthority-abc"
rm -f "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true
touch "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true
chmod 600 "${XAUTHORITY}" "${ICEAUTHORITY}" >/dev/null 2>&1 || true

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

# If the base compositor already started Xwayland, reuse it.
for n in 0 1 2 3 4 5 6 7 8 9; do
  if [ -S "/tmp/.X11-unix/X${n}" ]; then
    display_num="$n"
    break
  fi
done

if [ -z "${display_num}" ]; then
  # Try to start our own rootless Xwayland on a free display.
  for n in 0 1 2 3 4 5 6 7 8 9; do
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

    # Seed ICEauthority as well; ksmserver uses ICE for session management.
    if command -v iceauth >/dev/null 2>&1; then
      ice_cookie="$( (command -v mcookie >/dev/null 2>&1 && mcookie) || (openssl rand -hex 16 2>/dev/null) || echo "" )"
      if [ -n "${ice_cookie}" ]; then
        host="$(hostname 2>/dev/null || echo "")"
        set +e

        # Try a couple of common network-id spellings.
        for netid in \
          "${DISPLAY}" \
          "unix${DISPLAY}" \
          "local/unix${DISPLAY}" \
          "local/${DISPLAY}" \
          "${host}/unix${DISPLAY}" \
          "${host}${DISPLAY}" \
          "localhost/unix${DISPLAY}" \
          "localhost${DISPLAY}"; do
          [ -n "${netid}" ] || continue
          iceauth -f "${ICEAUTHORITY}" remove "${netid}" MIT-MAGIC-COOKIE-1 >/dev/null 2>&1
          iceauth -f "${ICEAUTHORITY}" add "${netid}" MIT-MAGIC-COOKIE-1 "${ice_cookie}" >/dev/null 2>&1
        done

        # Some iceauth builds don't support the CLI subcommand form reliably.
        # If the file is still empty, feed commands on stdin.
        if [ ! -s "${ICEAUTHORITY}" ]; then
          tmpcmd="${TMPDIR:-/tmp}/iceauth.cmd.$$"
          {
            for netid in \
              "${DISPLAY}" \
              "unix${DISPLAY}" \
              "local/unix${DISPLAY}" \
              "local/${DISPLAY}" \
              "${host}/unix${DISPLAY}" \
              "${host}${DISPLAY}" \
              "localhost/unix${DISPLAY}" \
              "localhost${DISPLAY}"; do
              [ -n "${netid}" ] || continue
              echo "remove ${netid} MIT-MAGIC-COOKIE-1"
              echo "add ${netid} MIT-MAGIC-COOKIE-1 ${ice_cookie}"
            done
            echo "quit"
          } >"${tmpcmd}" 2>/dev/null

          iceauth -f "${ICEAUTHORITY}" <"${tmpcmd}" >/dev/null 2>&1
          rm -f "${tmpcmd}" >/dev/null 2>&1 || true
        fi

        set -e
      fi
    fi

    log "Starting Xwayland on DISPLAY=${DISPLAY} (rootless on ${WAYLAND_DISPLAY})"
    # -ac disables access control; inside a container this avoids brittle Xauthority issues.
    run_as_abc Xwayland "${DISPLAY}" -rootless -noreset -nolisten tcp -ac -auth "${XAUTHORITY}" >/config/xwayland.log 2>&1 &
    xwpid=$!

    i=0
    while [ $i -lt 30 ]; do
      if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
        break
      fi
      if ! kill -0 "${xwpid}" >/dev/null 2>&1; then
        log "ERROR: Xwayland exited early (pid=${xwpid}); see /config/xwayland.log"
        break
      fi
      sleep 1
      i=$((i + 1))
    done

    if [ -S "/tmp/.X11-unix/X${display_num}" ]; then
      break
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
  while [ $i -lt 30 ]; do
    if run_as_abc xdpyinfo -display "${DISPLAY}" >/dev/null 2>&1; then
      break
    fi
    sleep 1
    i=$((i + 1))
  done
  if [ $i -ge 30 ]; then
    log "WARNING: X did not become ready within 30s; continuing anyway"
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
