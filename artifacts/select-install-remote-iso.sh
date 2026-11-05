#!/bin/bash -eu
# Point the install ISO fields in config.yaml at a remote release server,
# optionally through the artifact server's proxy paths. Remote counterpart
# of select-install-iso.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.yaml}"
source "$SCRIPT_DIR/lib/remote-iso.sh"

usage() {
  cat <<EOF
Usage: $0 [--release-server URL] [--proxy | --proxy-insecure] [VERSION]

Check that the release files exist on the remote server, then set
harvester_version and harvester_{iso,kernel,ramdisk,rootfs}_url in
config.yaml to point at them.

$(remote_iso_options_help)

Examples:
  $0 v1.8.1
  $0 --proxy master
  $0 --release-server https://10.10.0.100/harvester --proxy-insecure v1.8.1
EOF
}

remote_iso_parse_args "$@"

ISO_URL=$(remote_url "$NAME-amd64.iso")
KERNEL_URL=$(remote_url "$NAME-vmlinuz-amd64")
RAMDISK_URL=$(remote_url "$NAME-initrd-amd64")
ROOTFS_URL=$(remote_url "$NAME-rootfs-amd64.squashfs")

remote_iso_check "$ISO_URL" "$KERNEL_URL" "$RAMDISK_URL" "$ROOTFS_URL" -- \
  "$(remote_url "$NAME-amd64.sha512")" "$(remote_url version.yaml)"

echo "Updating config.yaml..."

# Update config.yaml using sed to preserve formatting
sed -i "s|^harvester_version:.*|harvester_version: $NAME|" "$CONFIG_FILE"
sed -i "s|^harvester_iso_url:.*|harvester_iso_url: $ISO_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_kernel_url:.*|harvester_kernel_url: $KERNEL_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_ramdisk_url:.*|harvester_ramdisk_url: $RAMDISK_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_rootfs_url:.*|harvester_rootfs_url: $ROOTFS_URL|" "$CONFIG_FILE"

echo "Configuration updated successfully!"
echo ""
echo "Current settings:"
echo "  ISO: $(yq '.harvester_iso_url' "$CONFIG_FILE")"
echo "  Kernel: $(yq '.harvester_kernel_url' "$CONFIG_FILE")"
echo "  Initrd: $(yq '.harvester_ramdisk_url' "$CONFIG_FILE")"
echo "  Rootfs: $(yq '.harvester_rootfs_url' "$CONFIG_FILE")"
