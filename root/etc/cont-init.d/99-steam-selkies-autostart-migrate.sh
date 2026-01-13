#!/bin/bash
set -e

install_kde_autostart_if_legacy() {
  local target="/config/.config/openbox/autostart"
  local desired="/defaults/autostart"

  [ -r "${desired}" ] || return 0

  # If the user has never created the Openbox autostart, let the base image copy defaults.
  if [ ! -f "${target}" ]; then
    return 0
  fi

  # If the user already has a KDE-managed autostart, leave it alone.
  if grep -q 'steam-selkies-managed:desktop=kde' "${target}" 2>/dev/null; then
    return 0
  fi

  # Only replace the autostart if it looks like the legacy minimal one:
  # - starts Sunshine
  # - launches Steam directly
  # - does not mention Plasma
  if grep -q '^# Start Sunshine' "${target}" \
    && grep -Eq '^[[:space:]]*(steam|steam-selkies)[[:space:]]*$' "${target}" \
    && ! grep -q 'startplasma' "${target}"; then
    cp -f "${target}" "${target}.bak.$(date +%s)" 2>/dev/null || true
    cp -f "${desired}" "${target}"
    chmod +x "${target}" || true
    echo "[steam-selkies] Updated Openbox autostart to KDE launcher: ${target}"
  fi
}

fix_autostart() {
  local file="$1"

  if [ ! -f "$file" ]; then
    return 0
  fi

  # Only touch the historical autostart contents we shipped earlier:
  # it had a "# Launch Steam." comment and a single "steam" line.
  if grep -qx '# Launch Steam\.' "$file" && grep -Eq '^[[:space:]]*steam[[:space:]]*$' "$file" && ! grep -q 'steam-selkies' "$file"; then
    sed -i -E 's/^([[:space:]]*)steam[[:space:]]*$/\1steam-selkies/' "$file"
  fi

  # Wayland variant comment used in the earlier file.
  if grep -qx '# Steam will run via XWayland in the Wayland session\.' "$file" && grep -Eq '^[[:space:]]*steam[[:space:]]*$' "$file" && ! grep -q 'steam-selkies' "$file"; then
    sed -i -E 's/^([[:space:]]*)steam[[:space:]]*$/\1steam-selkies/' "$file"
  fi

  # Encourage a stable debugging experience even with a persisted /config:
  # insert the optional smoke-test launcher ahead of Steam if it isn't present.
  # The helper is a no-op unless STEAM_DEBUG_SMOKE_TEST=true.
  if grep -Eq '^[[:space:]]*steam-selkies\b' "$file" && ! grep -Eq '^[[:space:]]*selkies-smoke-test\b' "$file"; then
    # Insert immediately before the first steam-selkies invocation, preserving indentation.
    sed -i -E '0,/^([[:space:]]*)steam-selkies\b/ s//\1selkies-smoke-test\n\1steam-selkies/' "$file"
  fi
}

fix_autostart /config/.config/openbox/autostart
fix_autostart /config/.config/wayfire/autostart
fix_autostart /config/.config/labwc/autostart

install_kde_autostart_if_legacy
