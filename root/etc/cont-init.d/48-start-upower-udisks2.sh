#!/bin/bash
set -euo pipefail

log() {
  echo "[steam-selkies] $*"
}

wait_for_system_dbus() {
  # In LSIO base images, cont-init can run before the system bus is fully up.
  # If we start daemons too early, they can exit immediately and KDE/Steam will
  # trigger repeated D-Bus activation attempts (and log spam).
  local sock="/run/dbus/system_bus_socket"
  local _
  for _ in {1..50}; do
    if [ -S "${sock}" ]; then
      return 0
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
      "${p}" >/dev/null 2>&1 &
      # Give it a moment to connect to the system bus and claim its name.
      sleep 0.3
      return 0
    fi
  done

  return 0
}

if wait_for_system_dbus; then
  log "System D-Bus socket is available; starting D-Bus-activated helpers proactively"
else
  log "WARNING: system D-Bus socket not ready; starting helpers anyway (they may not register)" >&2
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
