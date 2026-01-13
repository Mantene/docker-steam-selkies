#!/bin/bash
set -euo pipefail

# Ensure D-Bus system service activation works in linuxserver base images.
#
# In these images, the system bus may run as user 'abc'. D-Bus uses the setuid helper
# /usr/lib/dbus-1.0/dbus-daemon-launch-helper for service activation. dbus-daemon
# refuses to use the helper unless:
# - helper is root:messagebus and mode 4754 (matches Debian packaging)
# - the path to the helper is not writable by group/other (trusted path)
# - the bus user can execute it (usually by being in messagebus group)

log() {
	echo "[steam-selkies][dbus-helper] $*"
	echo "[steam-selkies][dbus-helper] $*" >>/config/steam-selkies.log 2>/dev/null || true
}

helper=/usr/lib/dbus-1.0/dbus-daemon-launch-helper

if ! command -v getent >/dev/null 2>&1; then
	exit 0
fi

if ! getent group messagebus >/dev/null 2>&1; then
	log "messagebus group not present; skipping"
	exit 0
fi

if id abc >/dev/null 2>&1; then
	if ! id -nG abc | tr ' ' '\n' | grep -qx messagebus; then
		if command -v usermod >/dev/null 2>&1; then
			usermod -aG messagebus abc || true
			log "Added abc to messagebus group"
		else
			log "WARNING: usermod not available; cannot add abc to messagebus group"
		fi
	fi
fi

if [ ! -e "${helper}" ]; then
	log "WARNING: ${helper} not found; activation may fail"
	exit 0
fi

log "Before: $(stat -c '%a %A %U:%G %n' /usr /usr/lib /usr/lib/dbus-1.0 "${helper}" 2>/dev/null | tr '\n' '|' || true)"

# Harden the path (best-effort; log if read-only).
for d in /usr /usr/lib /usr/lib/dbus-1.0; do
	if [ -d "${d}" ]; then
		chown root:root "${d}" 2>/dev/null || true
		chmod go-w "${d}" 2>/dev/null || true
	fi
done

# Enforce helper ownership/mode.
chown root:messagebus "${helper}" 2>/dev/null || true
chmod 4754 "${helper}" 2>/dev/null || true

log "After:  $(stat -c '%a %A %U:%G %n' /usr /usr/lib /usr/lib/dbus-1.0 "${helper}" 2>/dev/null | tr '\n' '|' || true)"
