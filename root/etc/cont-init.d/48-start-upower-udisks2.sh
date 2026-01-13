#!/bin/bash
set -euo pipefail

log() {
  echo "[steam-selkies] $*"
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
      return 0
    fi
  done

  return 0
}

# These services are commonly activated via the D-Bus setuid helper.
# If the host/container environment blocks servicehelper (common on some NAS setups),
# KDE will repeatedly log activation failures. Starting them proactively avoids that path.
start_daemon_if_present upowerd \
  /usr/libexec/upowerd \
  /usr/lib/upower/upowerd \
  /usr/libexec/upower/upowerd

start_daemon_if_present udisksd \
  /usr/libexec/udisks2/udisksd \
  /usr/lib/udisks2/udisksd \
  /usr/libexec/udisks/udisksd \
  /usr/lib/udisks/udisksd
