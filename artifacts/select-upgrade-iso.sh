#!/bin/bash -eu
# Point the upgrade test ISO in config.yaml at a version downloaded to
# artifacts/isos/<prefix>/<version>/ and served by the artifact server.
# Local counterpart of select-upgrade-remote-iso.sh.
#
# Usage: select-upgrade-iso.sh [VERSION]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.yaml}"
ISOS_DIR="${ISOS_DIR:-$SCRIPT_DIR/isos}"
source "$SCRIPT_DIR/lib/local-iso.sh"

local_iso_select "$@"

ISO_URL=$(local_url "$NAME-amd64.iso")

echo "Updating config.yaml..."

yq -e -i ".tests.upgrade.iso_url = \"$ISO_URL\"" "$CONFIG_FILE"

echo "Configuration updated successfully!"
echo ""
echo "Current settings:"
echo "  ISO: $(yq '.tests.upgrade.iso_url' "$CONFIG_FILE")"
