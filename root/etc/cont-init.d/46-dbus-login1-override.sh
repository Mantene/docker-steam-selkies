#!/bin/bash
set -euo pipefail

# Ensure org.freedesktop.login1 D-Bus activation uses elogind in non-systemd containers.

get_dbus_service_dirs() {
	local conf
	for conf in /etc/dbus-1/system.conf /usr/share/dbus-1/system.conf; do
		[ -f "${conf}" ] || continue
		sed -n 's:.*<servicedir>\(.*\)</servicedir>.*:\1:p' "${conf}" || true
	done
}

find_elogind_bin() {
	local p
	for p in \
		/lib/elogind/elogind \
		/libexec/elogind/elogind \
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

service_dirs="$(get_dbus_service_dirs | awk 'NF' | sort -u)"
if [ -z "${service_dirs}" ]; then
	service_dirs=$(cat <<'EOF'
/etc/dbus-1/system-services
/usr/local/share/dbus-1/system-services
/usr/share/dbus-1/system-services
EOF
)
fi

installed_any=false
while IFS= read -r dst_dir; do
	[ -n "${dst_dir}" ] || continue
	dst_file="${dst_dir}/org.freedesktop.login1.service"
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
	installed_any=true
done <<<"${service_dirs}"

if [ "${installed_any}" != "true" ]; then
	echo "[steam-selkies] WARNING: no D-Bus servicedir locations found; login1 override not installed" >&2
fi
