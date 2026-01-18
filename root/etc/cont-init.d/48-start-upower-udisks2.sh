#!/bin/bash
set -euo pipefail

# Some environments (notably when a daemon immediately SIGTRAPs under emulation
# or restricted sandboxes) can cause bash to emit noisy "Trace/breakpoint trap"
# job messages. We don't need job control here.
set +m

log() {
  echo "[steam-selkies] $*"
}

wait_for_system_dbus() {
  # In LSIO base images, cont-init can run before the system bus is fully up.
  # If we start daemons too early, they can exit immediately and KDE/Steam will
  # trigger repeated D-Bus activation attempts (and log spam).
  #
  # Allow a longer wait on slower hosts via STEAM_SELKIES_DBUS_WAIT_SECONDS.
  # Default is intentionally modest to not delay boot when the system bus will
  # never appear in a given environment.
  local wait_seconds="${1:-${STEAM_SELKIES_DBUS_WAIT_SECONDS:-15}}"
  local sock="/run/dbus/system_bus_socket"
  local ticks_max
  local tick
  ticks_max=$((wait_seconds * 10))
  if [ "${ticks_max}" -lt 1 ]; then
    ticks_max=1
  fi

  for ((tick = 0; tick < ticks_max; tick++)); do
    if [ -S "${sock}" ]; then
      # Socket existence isn't always enough; ensure dbus-daemon is responding.
      if command -v dbus-send >/dev/null 2>&1; then
        if dbus-send --system --print-reply --dest=org.freedesktop.DBus \
          /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
          return 0
        fi
      else
        return 0
      fi
    fi
    sleep 0.1
  done

  return 1
}

dbus_list_names_has() {
  local name="$1"
  if ! command -v dbus-send >/dev/null 2>&1; then
    return 1
  fi
  dbus-send --system --print-reply --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | grep -Fqx "string \"${name}\""
}

start_daemon_if_present() {
  local name="$1"
  shift

  if pgrep -f "(^|/)${name}(\\s|$)" >/dev/null 2>&1; then
    return 0
  fi

  local p
  for p in "$@"; do
    if [ -x "${p}" ] && [ ! -d "${p}" ]; then
      log "Starting ${name} via ${p}"

      # Start detached to avoid bash job-control signal messages if the daemon
      # crashes immediately (e.g., SIGTRAP under some emulators).
      if command -v setsid >/dev/null 2>&1; then
        setsid -f "${p}" >/dev/null 2>&1 || true
      else
        nohup "${p}" >/dev/null 2>&1 </dev/null &
        disown >/dev/null 2>&1 || true
      fi

      # Give it a moment to connect to the system bus and claim its name.
      sleep 0.4

      # Confirm it actually started; if not, try the next candidate path.
      if pgrep -f "(^|/)${name}(\\s|$)" >/dev/null 2>&1; then
        return 0
      fi

      log "WARNING: ${name} failed to stay running when started via ${p}" >&2
    fi
  done

  return 0
}

if wait_for_system_dbus; then
  log "System D-Bus is available; starting D-Bus-activated helpers proactively"
else
  if [ "${STEAM_SELKIES_HELPERS_FORCE_WITHOUT_DBUS:-false}" = "true" ]; then
    log "WARNING: system D-Bus not ready; forcing helper start anyway (may fail)" >&2
  else
    log "System D-Bus not ready; skipping upowerd/udisksd startup (set STEAM_SELKIES_HELPERS_FORCE_WITHOUT_DBUS=true to force)" >&2
    exit 0
  fi
fi

# These services are commonly activated via the D-Bus setuid helper.
# If the host/container environment blocks servicehelper (common on some NAS setups),
# KDE will repeatedly log activation failures. Starting them proactively avoids that path.
start_daemon_if_present upowerd \
  /usr/libexec/upowerd \
  /usr/lib/upower/upowerd \
  /usr/libexec/upower/upowerd

# If upowerd is available but did not register, leave a single hint line.
if command -v pgrep >/dev/null 2>&1 && pgrep -f "(^|/)upowerd(\\s|$)" >/dev/null 2>&1; then
  if ! dbus_list_names_has org.freedesktop.UPower; then
    log "WARNING: upowerd is running but org.freedesktop.UPower is not on the system bus (check D-Bus/servicehelper permissions)" >&2
  fi
fi

start_daemon_if_present udisksd \
  /usr/libexec/udisks2/udisksd \
  /usr/lib/udisks2/udisksd \
  /usr/libexec/udisks/udisksd \
  /usr/lib/udisks/udisksd

if command -v pgrep >/dev/null 2>&1 && pgrep -f "(^|/)udisksd(\\s|$)" >/dev/null 2>&1; then
  if ! dbus_list_names_has org.freedesktop.UDisks2; then
    log "WARNING: udisksd is running but org.freedesktop.UDisks2 is not on the system bus (check D-Bus/servicehelper permissions)" >&2
  fi
fi
