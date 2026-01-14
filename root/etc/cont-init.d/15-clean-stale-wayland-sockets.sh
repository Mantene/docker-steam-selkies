#!/bin/bash
set -euo pipefail

log() {
  echo "[steam-selkies] $*"
}

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

  if command -v socat >/dev/null 2>&1; then
    socat -T 1 - "UNIX-CONNECT:${sock_path}" </dev/null >/dev/null 2>&1
    return $?
  fi

  # If we can't test, don't delete anything.
  return 0
}

# The upstream s6 service that starts the desktop waits for socket *existence*.
# If a stale socket file is left behind in /config/.XDG, it can trigger startup
# too early, and rootless Xwayland will fail with ECONNREFUSED.
RUNTIME_DIR="/config/.XDG"

if [ ! -d "${RUNTIME_DIR}" ]; then
  exit 0
fi

shopt -s nullglob
stale_count=0
for sock in "${RUNTIME_DIR}"/wayland-*; do
  [ -S "${sock}" ] || continue

  out="$(wayland_can_connect "${sock}" 2>&1)" || {
    log "Removing stale Wayland socket (not connectable): ${sock} (${out:-unknown error})"
    rm -f "${sock}" >/dev/null 2>&1 || true
    stale_count=$((stale_count + 1))
    continue
  }
done

if [ "${stale_count}" -gt 0 ]; then
  log "Removed ${stale_count} stale Wayland socket(s) under ${RUNTIME_DIR}"
fi
