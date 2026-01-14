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
ensure_dir /config/.local 0755
ensure_dir /config/.local/share 0755
ensure_dir /config/.cache 0755
ensure_dir /config/Desktop 0755
ensure_dir /config/tmp 0700

# If these already exist but are owned by root, KDE will fail to update them.
chown -R "$uid:$gid" /config/.XDG /config/.config /config/.local /config/.cache /config/Desktop >/dev/null 2>&1 || true

# Ensure the main debug log is writable by abc; startwm scripts append very early.
touch /config/steam-selkies.log >/dev/null 2>&1 || true
chown "$uid:$gid" /config/steam-selkies.log >/dev/null 2>&1 || true
chmod 664 /config/steam-selkies.log >/dev/null 2>&1 || true

# Ensure auth files are owned by abc if they exist.
for f in /config/.Xauthority /config/.ICEauthority; do
  if [ -e "$f" ]; then
    chown "$uid:$gid" "$f" >/dev/null 2>&1 || true
    chmod 600 "$f" >/dev/null 2>&1 || true
  fi
done

# KDE frequently reads/writes these; if they were created with mode 000 due to odd host FS semantics,
# Plasma will spam errors and may lose places/bookmarks.
for f in /config/.local/share/user-places.xbel /config/.local/share/user-places.xbel.tbcache; do
  if [ -e "$f" ]; then
    chown "$uid:$gid" "$f" >/dev/null 2>&1 || true
    chmod 644 "$f" >/dev/null 2>&1 || true
  fi
done

echo "[steam-selkies] ensured /config ownership for abc (${uid}:${gid})"
