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
