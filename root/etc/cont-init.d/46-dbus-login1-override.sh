#!/bin/bash
set -euo pipefail

# Ensure org.freedesktop.login1 D-Bus activation uses elogind in non-systemd containers.
dst_dir=/etc/dbus-1/system-services
dst_file="${dst_dir}/org.freedesktop.login1.service"

find_elogind_bin() {
	local p
	for p in \
		/usr/lib/elogind/elogind \
		/usr/libexec/elogind/elogind \
		/usr/lib/elogind/elogind-daemon \
		/usr/sbin/elogind \
		/usr/bin/elogind; do
		if [ -x "${p}" ]; then
			echo "${p}"
			return 0
		fi
	done
	return 1
}

elogind_bin=""
if ! elogind_bin="$(find_elogind_bin)"; then
	echo "[steam-selkies] WARNING: elogind binary not found; cannot install D-Bus login1 override" >&2
	exit 0
fi

mkdir -p "${dst_dir}"

cat >"${dst_file}" <<'EOF'
[D-BUS Service]
Name=org.freedesktop.login1
Exec=ELOGIND_BIN
User=root
EOF

sed -i "s|^Exec=ELOGIND_BIN$|Exec=${elogind_bin}|" "${dst_file}"

chmod 0644 "${dst_file}"
echo "[steam-selkies] Installed D-Bus login1 override at ${dst_file} (Exec=${elogind_bin})"
