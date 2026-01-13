#!/bin/bash
set -euo pipefail

# Ensure D-Bus system service activation works in linuxserver base images.
#
# In these images, the system bus may run as user 'abc'. D-Bus uses the setuid helper
# /usr/lib/dbus-1.0/dbus-daemon-launch-helper for service activation. dbus-daemon
# refuses to use the helper unless:
# - helper is root:messagebus and mode 4750/4754 depending on distro/dbus build
# - the path to the helper is not writable by group/other (trusted path)
# - the bus user can execute it (usually by being in messagebus group)

log() {
	echo "[steam-selkies][dbus-helper] $*"
	echo "[steam-selkies][dbus-helper] $*" >>/config/steam-selkies.log 2>/dev/null || true
}

helper_candidates=(
	/usr/lib/dbus-1.0/dbus-daemon-launch-helper
	/usr/lib/x86_64-linux-gnu/dbus-1.0/dbus-daemon-launch-helper
	/lib/dbus-1.0/dbus-daemon-launch-helper
	/lib/x86_64-linux-gnu/dbus-1.0/dbus-daemon-launch-helper
)

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

found_any=false
for helper in "${helper_candidates[@]}"; do
	if [ -e "${helper}" ]; then
		found_any=true
		log "Before: $(stat -c '%a %A %U:%G %n' /usr /usr/lib /usr/lib/dbus-1.0 "${helper}" 2>/dev/null | tr '\n' '|' || true)"

		# Harden the path (best-effort; log if read-only).
		for d in /usr /usr/lib /usr/lib/dbus-1.0 /usr/lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/dbus-1.0; do
			if [ -d "${d}" ]; then
				chown root:root "${d}" 2>/dev/null || true
				chmod go-w "${d}" 2>/dev/null || true
			fi
		done

		# Enforce helper ownership/mode.
		chown root:messagebus "${helper}" 2>/dev/null || true
		chmod 4754 "${helper}" 2>/dev/null || true

		log "After:  $(stat -c '%a %A %U:%G %n' /usr /usr/lib /usr/lib/dbus-1.0 "${helper}" 2>/dev/null | tr '\n' '|' || true)"
	fi
done

if [ "${found_any}" = false ]; then
	log "WARNING: dbus-daemon-launch-helper not found in common paths; activation may fail"
	exit 0
fi
