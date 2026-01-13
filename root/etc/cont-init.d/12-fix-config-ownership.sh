#!/usr/bin/env bash
set -euo pipefail

# In linuxserver/baseimage-selkies, services typically run as user 'abc'.
# If any previous init run created /config dotfiles as root, KDE/Wayland startup
# can fail with "Permission denied". Fix common paths proactively.

if ! id abc >/dev/null 2>&1; then
  exit 0
fi

uid="$(id -u abc)"
gid="$(id -g abc)"

ensure_dir() {
  local d="$1"
  local mode="$2"
  mkdir -p "$d" || true
  chmod "$mode" "$d" >/dev/null 2>&1 || true
  chown "$uid:$gid" "$d" >/dev/null 2>&1 || true
}

ensure_dir /config 0755
ensure_dir /config/.XDG 0700
ensure_dir /config/.config 0755
ensure_dir /config/.config/autostart 0755
ensure_dir /config/Desktop 0755

# If these already exist but are owned by root, KDE will fail to update them.
chown -R "$uid:$gid" /config/.XDG /config/.config /config/Desktop >/dev/null 2>&1 || true

echo "[steam-selkies] ensured /config ownership for abc (${uid}:${gid})"
