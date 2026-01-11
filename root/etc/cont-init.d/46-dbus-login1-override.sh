#!/bin/bash
set -euo pipefail

# Ensure org.freedesktop.login1 D-Bus activation uses elogind in non-systemd containers.
dst_dir=/etc/dbus-1/system-services
dst_file="${dst_dir}/org.freedesktop.login1.service"

mkdir -p "${dst_dir}"

cat >"${dst_file}" <<'EOF'
[D-BUS Service]
Name=org.freedesktop.login1
Exec=/usr/local/bin/elogind-wrapper
User=root
EOF

chmod 0644 "${dst_file}"
echo "[steam-selkies] Installed D-Bus login1 override at ${dst_file}"
