#!/bin/bash
set -euo pipefail

# The system dbus-daemon in linuxserver base images often runs as user 'abc'.
# On Debian, dbus-daemon-launch-helper is typically mode 4754 root:messagebus,
# meaning only root and members of the messagebus group can execute it.
# If 'abc' isn't in that group, all system service activation will fail with
# "Failed to execute program ... Permission denied".

if ! command -v id >/dev/null 2>&1; then
	exit 0
fi

if ! id abc >/dev/null 2>&1; then
	exit 0
fi

if ! getent group messagebus >/dev/null 2>&1; then
	echo "[steam-selkies] messagebus group not present; skipping dbus helper perms"
	exit 0
fi

helper=/usr/lib/dbus-1.0/dbus-daemon-launch-helper
if [ -e "${helper}" ]; then
	# dbus-daemon validates that this helper is setuid root and owned by root:messagebus
	# with strict permissions; otherwise activation fails with PermissionsInvalid.
	if command -v chown >/dev/null 2>&1 && command -v chmod >/dev/null 2>&1; then
		# Also ensure the helper's parent directories are not writable by group/other.
		# dbus-daemon refuses to use the helper if any directory in its path is writable
		# by a non-root user.
		for d in /usr /usr/lib /usr/lib/dbus-1.0; do
			if [ -d "${d}" ]; then
				chown root:root "${d}" || true
				chmod go-w "${d}" || true
			fi
		done

		chown root:messagebus "${helper}" || true
			# Be strict: only root and messagebus group can read/execute.
			chmod 4750 "${helper}" || true
		# Best-effort log of resulting perms.
		ls -l "${helper}" || true
	else
		echo "[steam-selkies] WARNING: cannot validate ${helper} perms (missing chown/chmod)" >&2
	fi
else
	echo "[steam-selkies] WARNING: ${helper} not found; D-Bus activation may fail" >&2
fi

if id -nG abc | tr ' ' '\n' | grep -qx messagebus; then
	echo "[steam-selkies] abc already in messagebus group"
	exit 0
fi

if command -v usermod >/dev/null 2>&1; then
	usermod -aG messagebus abc
	echo "[steam-selkies] Added abc to messagebus group"
	# Note: existing processes won't pick this up; dbus-daemon may need restart.
	if pidof dbus-daemon >/dev/null 2>&1; then
		echo "[steam-selkies] NOTE: restart container for dbus group change to take effect"
	fi
	exit 0
fi

echo "[steam-selkies] WARNING: usermod not available; cannot add abc to messagebus group" >&2
