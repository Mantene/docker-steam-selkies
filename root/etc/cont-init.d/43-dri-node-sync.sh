#!/usr/bin/env bash
set -euo pipefail

# Selkies exposes the active DRM node to its Wayland/KMS backend via DRI_NODE.
# Some templates/docs historically used DRINODE.
# If DRI_NODE points at a render node (e.g. /dev/dri/renderD128), KMS ioctls can
# fail (often resulting in a black stream even though capture "starts").
#
# Fix: in Wayland mode, prefer a card node (e.g. /dev/dri/card0) unless the user
# explicitly set DRI_NODE to something else.

if [ "${PIXELFLUX_WAYLAND:-}" != "true" ]; then
  exit 0
fi

mkdir -p /etc/cont-env.d

# Helper: write env var into /etc/cont-env.d (picked up by s6 services).
write_env() {
  local name="$1"
  local value="$2"

  printf '%s' "${value}" >"/etc/cont-env.d/${name}"
}

legacy_drinode="${DRINODE:-}"
current_dri_node="${DRI_NODE:-}"

preferred_card_node=""
if [ -n "${legacy_drinode}" ]; then
  preferred_card_node="${legacy_drinode}"
elif [ -e /dev/dri/card0 ]; then
  preferred_card_node="/dev/dri/card0"
fi

is_render_node=false
if [ -n "${current_dri_node}" ] && printf '%s' "${current_dri_node}" | grep -Eq '^/dev/dri/renderD[0-9]+$'; then
  is_render_node=true
fi

should_override=false

# If DRI_NODE is unset, set it.
if [ -z "${current_dri_node}" ] && [ -n "${preferred_card_node}" ]; then
  should_override=true
fi

# If the base image defaulted DRI_NODE to a render node, override to a card node.
if [ "${is_render_node}" = "true" ] && [ -n "${preferred_card_node}" ]; then
  should_override=true
fi

if [ "${should_override}" = "true" ] && [ -n "${preferred_card_node}" ]; then
  export DRI_NODE="${preferred_card_node}"
  export DRINODE="${preferred_card_node}"
  write_env "DRI_NODE" "${preferred_card_node}"
  write_env "DRINODE" "${preferred_card_node}"
  echo "[steam-selkies] PIXELFLUX_WAYLAND=true -> using card DRM node ${preferred_card_node} (was DRI_NODE='${current_dri_node:-}' DRINODE='${legacy_drinode:-}')"
fi
