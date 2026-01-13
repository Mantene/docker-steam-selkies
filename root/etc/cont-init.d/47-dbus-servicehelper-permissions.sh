#!/bin/bash
set -euo pipefail

# Backwards-compatible wrapper: the hardening logic lives in 11-dbus-servicehelper-hardening.sh
exec /custom-cont-init.d/11-dbus-servicehelper-hardening.sh
