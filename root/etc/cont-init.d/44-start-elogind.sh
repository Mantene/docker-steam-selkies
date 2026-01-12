#!/bin/bash
set -euo pipefail

# Start elogind proactively so clients (Steam, etc.) can talk to org.freedesktop.login1
# without relying on D-Bus service activation via dbus-daemon-launch-helper.

if ! command -v pgrep >/dev/null 2>&1; then
	exit 0
fi

if pgrep -f "^/usr/libexec/elogind(\s|$)" >/dev/null 2>&1 || pgrep -x elogind >/dev/null 2>&1; then
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

if [ -x /usr/libexec/elogind ]; then
	echo "[steam-selkies] Starting elogind via /usr/libexec/elogind"
	# elogind should daemonize itself when run without options.
	# Run it in background so cont-init can proceed.
	/usr/libexec/elogind &
	exit 0
fi

echo "[steam-selkies] WARNING: elogind not found; login1 may be unavailable" >&2
