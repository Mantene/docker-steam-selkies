#!/bin/bash
set -e

fix_autostart() {
  local file="$1"

  if [ ! -f "$file" ]; then
    return 0
  fi

  # Only touch the historical autostart contents we shipped earlier:
  # it had a "# Launch Steam." comment and a single "steam" line.
  if grep -qx '# Launch Steam\.' "$file" && grep -qx 'steam' "$file" && ! grep -q 'steam-selkies' "$file"; then
    sed -i 's/^steam$/steam-selkies/' "$file"
  fi

  # Wayland variant comment used in the earlier file.
  if grep -qx '# Steam will run via XWayland in the Wayland session\.' "$file" && grep -qx 'steam' "$file" && ! grep -q 'steam-selkies' "$file"; then
    sed -i 's/^steam$/steam-selkies/' "$file"
  fi

  # Encourage a stable debugging experience even with a persisted /config:
  # insert the optional smoke-test launcher ahead of Steam if it isn't present.
  # The helper is a no-op unless STEAM_DEBUG_SMOKE_TEST=true.
  if grep -q '^steam-selkies\b' "$file" && ! grep -q '^selkies-smoke-test\b' "$file"; then
    # Insert immediately before the first steam-selkies invocation.
    sed -i '/^steam-selkies\b/i\selkies-smoke-test' "$file"
  fi
}

fix_autostart /config/.config/openbox/autostart
fix_autostart /config/.config/wayfire/autostart
fix_autostart /config/.config/labwc/autostart
