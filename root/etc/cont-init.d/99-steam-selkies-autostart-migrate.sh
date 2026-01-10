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
}

fix_autostart /config/.config/openbox/autostart
fix_autostart /config/.config/wayfire/autostart
