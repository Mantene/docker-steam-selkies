#!/bin/bash
set -euo pipefail

# Start elogind proactively so clients (Steam, etc.) can talk to org.freedesktop.login1
# without relying on D-Bus service activation via dbus-daemon-launch-helper.

if ! command -v pgrep >/dev/null 2>&1; then
	exit 0
fi

if pgrep -f "(^|/)elogind(\s|$)" >/dev/null 2>&1; then
	echo "[steam-selkies] elogind already running"
	exit 0
fi

if [ -x /etc/init.d/elogind ]; then
	echo "[steam-selkies] Starting elogind via /etc/init.d/elogind"
	set +e
	/etc/init.d/elogind start
	rc=$?
	set -e
	if [ $rc -ne 0 ]; then
		echo "[steam-selkies] WARNING: /etc/init.d/elogind start failed (rc=${rc})" >&2
	fi
	# Don't hard-fail; some environments may still run without login1.
	exit 0
fi

for p in \
	/usr/lib/elogind/elogind \
	/lib/elogind/elogind \
	/usr/libexec/elogind/elogind \
	/libexec/elogind/elogind \
	/usr/sbin/elogind \
	/usr/bin/elogind; do
	if [ -x "${p}" ]; then
		echo "[steam-selkies] Starting elogind via ${p}"
		"${p}" &
		exit 0
	fi
done

# Fallback: ask dpkg where the package installed the daemon.
if command -v dpkg-query >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
	if dpkg-query -W -f='${Status}' elogind 2>/dev/null | grep -q "installed"; then
		while IFS= read -r p; do
			[ -n "${p}" ] || continue
			if [ -x "${p}" ] && echo "${p}" | grep -Eq '/elogind$'; then
				echo "[steam-selkies] Starting elogind via ${p} (dpkg -L)"
				"${p}" &
				exit 0
			fi
		done < <(dpkg -L elogind 2>/dev/null || true)
	fi
fi

echo "[steam-selkies] WARNING: elogind not found; login1 may be unavailable" >&2
