#!/bin/bash -eu
# Point the upgrade test ISO in config.yaml at a remote release server,
# optionally through the artifact server's proxy paths. Remote counterpart
# of select-upgrade-iso.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.yaml}"
source "$SCRIPT_DIR/lib/remote-iso.sh"

usage() {
  cat <<EOF
Usage: $0 [--release-server URL] [--proxy | --proxy-insecure] [VERSION]

Check that the release ISO exists on the remote server, then set
.tests.upgrade.iso_url in config.yaml to point at it.

$(remote_iso_options_help)

Examples:
  $0 v1.8.1
  $0 --proxy master
  $0 --release-server https://10.10.0.100/harvester --proxy-insecure v1.8.1
EOF
}

remote_iso_parse_args "$@"

ISO_URL=$(remote_url "$NAME-amd64.iso")

remote_iso_check "$ISO_URL" -- \
  "$(remote_url "$NAME-amd64.sha512")" "$(remote_url version.yaml)"

echo "Updating config.yaml..."

yq -e -i ".tests.upgrade.iso_url = \"$ISO_URL\"" "$CONFIG_FILE"

echo "Configuration updated successfully!"
echo ""
echo "Current settings:"
echo "  ISO: $(yq '.tests.upgrade.iso_url' "$CONFIG_FILE")"
