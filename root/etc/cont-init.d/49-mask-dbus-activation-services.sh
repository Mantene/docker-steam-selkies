#!/bin/bash
set -euo pipefail

# Mask noisy D-Bus activatable services when service activation via servicehelper is broken.
#
# Problem:
#   dbus-daemon (system bus) logs repeatedly:
#     "Activated service 'org.freedesktop.UPower' failed: The permission of the setuid helper is not correct"
#   This typically happens when the container runtime blocks setuid escalation (e.g., no_new_privs,
#   userns restrictions, hardened security profiles), or when the helper path cannot be trusted.
#
# Goal:
#   Stop the Docker log spam by preventing repeated activation attempts for known noisy services.
#   Apps will see these services as "not activatable" (unless you start them manually).
#
# Controls:
#   STEAM_DBUS_ACTIVATION_MASK:
#     - off  : do nothing
#     - on   : always mask these services
#     - auto : mask only if a quick activation probe fails (default)

log() {
  echo "[steam-selkies][dbus-mask] $*"
}

mode="${STEAM_DBUS_ACTIVATION_MASK:-auto}"

case "${mode}" in
  off|on|auto) ;;
  *)
    log "Unknown STEAM_DBUS_ACTIVATION_MASK='${mode}' (expected off|on|auto); treating as auto"
    mode="auto"
    ;;
 esac

wait_for_system_dbus() {
  local sock="/run/dbus/system_bus_socket"
  local _
  for _ in {1..50}; do
    [ -S "${sock}" ] && return 0
    sleep 0.1
  done
  return 1
}

get_service_dirs() {
  # Prefer configured servicedirs when possible.
  local conf
  for conf in /etc/dbus-1/system.conf /usr/share/dbus-1/system.conf; do
    [ -f "${conf}" ] || continue
    sed -n 's:.*<servicedir>\(.*\)</servicedir>.*:\1:p' "${conf}" || true
  done

  # Fallback to common defaults.
  cat <<'EOF'
/etc/dbus-1/system-services
/usr/local/share/dbus-1/system-services
/usr/share/dbus-1/system-services
EOF
}

mask_service() {
  local name="$1"
  local dst_dir
  local masked_any=false

  while IFS= read -r dst_dir; do
    [ -n "${dst_dir}" ] || continue
    # There may be multiple service dirs; mask wherever present.
    local f="${dst_dir}/${name}.service"
    if [ -f "${f}" ]; then
      local disabled="${f}.disabled"
      if [ -f "${disabled}" ]; then
        # Already masked.
        masked_any=true
        continue
      fi
      if mv -f "${f}" "${disabled}" 2>/dev/null; then
        log "Masked ${name} activation: ${f} -> ${disabled}"
        masked_any=true
      else
        log "WARNING: failed to mask ${f} (read-only rootfs?)"
      fi
    fi
  done < <(get_service_dirs | awk 'NF' | sort -u)

  if [ "${masked_any}" = false ]; then
    log "No ${name}.service found to mask"
  fi
}

activation_probe_fails() {
  # Returns 0 if activation seems broken.
  command -v dbus-send >/dev/null 2>&1 || return 0
  wait_for_system_dbus || return 0

  # Probe a single StartServiceByName. If servicehelper is blocked, this typically fails.
  # We silence stderr here because the whole point is to avoid echoing the failure again.
  dbus-send --system --print-reply --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus org.freedesktop.DBus.StartServiceByName \
    string:org.freedesktop.UPower uint32:0 >/dev/null 2>/dev/null || return 0

  return 1
}

if [ "${mode}" = "auto" ]; then
  if activation_probe_fails; then
    log "Detected broken D-Bus service activation (servicehelper); masking noisy activatable services"
    mode="on"
  else
    log "D-Bus activation probe succeeded; leaving activatable services enabled"
    exit 0
  fi
fi

if [ "${mode}" = "on" ]; then
  # Mask the top offenders from your logs.
  mask_service org.freedesktop.UPower
  mask_service org.freedesktop.UDisks2
  mask_service org.freedesktop.login1
fi
