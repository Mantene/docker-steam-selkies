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

try_cmd() {
	# Run a command and log a warning if it fails.
	# Usage: try_cmd <label> <cmd...>
	local label="$1"
	shift
	local err
	err="$({ "$@"; } 2>&1)" || {
		log "WARNING: ${label} failed: ${err}"
		return 1
	}
	return 0
}

log_fs_context() {
	local path="$1"
	if command -v findmnt >/dev/null 2>&1; then
		# Helpful for diagnosing read-only/nosuid mounts.
		local info
		info="$(findmnt -no TARGET,SOURCE,FSTYPE,OPTIONS --target "${path}" 2>/dev/null || true)"
		[ -n "${info}" ] && log "Mount: ${info}"
	fi
}

helper_candidates=(
	/usr/lib/dbus-1.0/dbus-daemon-launch-helper
	/usr/lib/x86_64-linux-gnu/dbus-1.0/dbus-daemon-launch-helper
	/lib/dbus-1.0/dbus-daemon-launch-helper
	/lib/x86_64-linux-gnu/dbus-1.0/dbus-daemon-launch-helper
)

# Discover additional helpers from package metadata (best-effort).
if command -v dpkg-query >/dev/null 2>&1 && command -v dpkg >/dev/null 2>&1; then
	if dpkg-query -W -f='${Status}' dbus 2>/dev/null | grep -q "installed"; then
		while IFS= read -r p; do
			[ -n "${p}" ] || continue
			case "${p}" in
				*/dbus-daemon-launch-helper)
					helper_candidates+=("${p}")
					;;
			esac
		done < <(dpkg -L dbus 2>/dev/null || true)
	fi
fi

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
		helper_dir="$(dirname "${helper}")"
		log "Helper: ${helper}"
		log "Before: $(stat -c '%a %A %U:%G %n' "${helper_dir}" "${helper}" 2>/dev/null | tr '\n' '|' || true)"

		# Harden the path (best-effort; log if read-only).
		for d in / /usr /lib /usr/lib \
			/usr/lib/dbus-1.0 /lib/dbus-1.0 \
			/usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu \
			/usr/lib/x86_64-linux-gnu/dbus-1.0 /lib/x86_64-linux-gnu/dbus-1.0 \
			"${helper_dir}"; do
			if [ -d "${d}" ]; then
				chown root:root "${d}" 2>/dev/null || true
				chmod go-w "${d}" 2>/dev/null || true
			fi
		done

		# Enforce helper ownership/mode.
		try_cmd "chown root:messagebus ${helper}" chown root:messagebus "${helper}" || true

		# Some dbus builds require the helper to be non-world-readable (4750).
		# If it is more permissive, dbus logs: "The permission of the setuid helper is not correct".
		if ! try_cmd "chmod 4750 ${helper}" chmod 4750 "${helper}"; then
			log_fs_context "${helper}"
		fi

		# If perms didn't change, call it out explicitly (common with read-only rootfs or restricted caps).
		mode_after="$(stat -c '%a' "${helper}" 2>/dev/null || true)"
		if [ "${mode_after}" != "4750" ]; then
			log "WARNING: helper mode is '${mode_after}' (wanted 4750); D-Bus activation may still spam logs"
			log_fs_context "${helper}"
		fi

		log "After:  $(stat -c '%a %A %U:%G %n' "${helper_dir}" "${helper}" 2>/dev/null | tr '\n' '|' || true)"
	fi
done

if [ "${found_any}" = false ]; then
	log "WARNING: dbus-daemon-launch-helper not found in common paths; activation may fail"
	exit 0
fi
