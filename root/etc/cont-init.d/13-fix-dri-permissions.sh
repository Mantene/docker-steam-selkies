#!/usr/bin/env bash
set -euo pipefail

# Ensure the linuxserver runtime user (abc) can access DRM devices.
# If /dev/dri/* is mapped from the host, nodes often come in as root:<gid> 660.
# When abc isn't in that gid, kwin_wayland/wlroots will fail with EPERM.

if ! id abc >/dev/null 2>&1; then
  exit 0
fi

if [ ! -d /dev/dri ]; then
  exit 0
fi

ensure_group_for_gid() {
  local gid="$1"
  local name="$2"

  [ -n "$gid" ] || return 1

  # Don't try to create/attach root group via this helper.
  if [ "$gid" = "0" ]; then
    return 0
  fi

  if getent group "$gid" >/dev/null 2>&1; then
    return 0
  fi

  if command -v groupadd >/dev/null 2>&1; then
    groupadd -g "$gid" "$name" >/dev/null 2>&1 || true
  else
    # Minimal fallback: append a group line.
    echo "$name:x:$gid:" >>/etc/group || true
  fi
}

add_abc_to_gid() {
  local gid="$1"
  [ -n "$gid" ] || return 0
  if [ "$gid" = "0" ]; then
    return 0
  fi

  local grp
  grp="$(getent group "$gid" | awk -F: '{print $1}' | head -n1)"
  [ -n "$grp" ] || return 0

  if command -v usermod >/dev/null 2>&1; then
    usermod -a -G "$grp" abc >/dev/null 2>&1 || true
  else
    # If usermod isn't present, we can't reliably modify groups.
    true
  fi
}

seen_any=false
for node in /dev/dri/card* /dev/dri/renderD*; do
  [ -e "$node" ] || continue
  seen_any=true

  gid="$(stat -c %g "$node" 2>/dev/null || true)"
  [ -n "$gid" ] || continue

  # Create deterministic group names so getent works.
  base="$(basename "$node")"
  ensure_group_for_gid "$gid" "drm_${base}" || true
  add_abc_to_gid "$gid" || true
done

if [ "$seen_any" = "true" ]; then
  echo "[steam-selkies] ensured abc has access to /dev/dri (abc groups: $(id -nG abc 2>/dev/null || true))"
fi
