#!/bin/bash -eu
# Point the install ISO fields in config.yaml at a version downloaded to
# artifacts/isos/<prefix>/<version>/ and served by the artifact server.
# Local counterpart of select-install-remote-iso.sh.
#
# Usage: select-install-iso.sh [VERSION]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.yaml}"
ISOS_DIR="${ISOS_DIR:-$SCRIPT_DIR/isos}"
source "$SCRIPT_DIR/lib/local-iso.sh"

local_iso_select "$@"

ISO_URL=$(local_url "$NAME-amd64.iso")
KERNEL_URL=$(local_url "$NAME-vmlinuz-amd64")
RAMDISK_URL=$(local_url "$NAME-initrd-amd64")
ROOTFS_URL=$(local_url "$NAME-rootfs-amd64.squashfs")

echo "Updating config.yaml..."

# Update config.yaml using sed to preserve formatting
sed -i "s|^harvester_version:.*|harvester_version: $VERSION|" "$CONFIG_FILE"
sed -i "s|^harvester_iso_url:.*|harvester_iso_url: $ISO_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_kernel_url:.*|harvester_kernel_url: $KERNEL_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_ramdisk_url:.*|harvester_ramdisk_url: $RAMDISK_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_rootfs_url:.*|harvester_rootfs_url: $ROOTFS_URL|" "$CONFIG_FILE"

echo "Configuration updated successfully!"
echo ""
echo "Current settings:"
echo "  Version: $(yq '.harvester_version' "$CONFIG_FILE")"
echo "  ISO: $(yq '.harvester_iso_url' "$CONFIG_FILE")"
echo "  Kernel: $(yq '.harvester_kernel_url' "$CONFIG_FILE")"
echo "  Initrd: $(yq '.harvester_ramdisk_url' "$CONFIG_FILE")"
echo "  Rootfs: $(yq '.harvester_rootfs_url' "$CONFIG_FILE")"
