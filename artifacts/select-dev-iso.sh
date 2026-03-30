#!/bin/bash -eu
# Switch to development/custom ISO URLs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.yaml"

# Default dev server settings
DEFAULT_DEV_SERVER="http://192.168.2.133"
DEFAULT_DEV_PATH="harvester"

# Parse arguments
if [ $# -eq 0 ]; then
  DEV_SERVER="$DEFAULT_DEV_SERVER"
  DEV_PATH="$DEFAULT_DEV_PATH"
elif [ $# -eq 1 ]; then
  DEV_SERVER="$1"
  DEV_PATH="$DEFAULT_DEV_PATH"
elif [ $# -eq 2 ]; then
  DEV_SERVER="$1"
  DEV_PATH="$2"
else
  echo "Usage: $0 [dev_server_url] [path]"
  echo ""
  echo "Examples:"
  echo "  $0                                    # Use default: $DEFAULT_DEV_SERVER/$DEFAULT_DEV_PATH"
  echo "  $0 http://192.168.2.133              # Custom server with default path"
  echo "  $0 http://192.168.2.133 harvester    # Custom server and path"
  exit 1
fi

# Construct URLs
ISO_URL="$DEV_SERVER/$DEV_PATH/harvester.iso"
KERNEL_URL="$DEV_SERVER/$DEV_PATH/vmlinuz"
RAMDISK_URL="$DEV_SERVER/$DEV_PATH/initrd"
ROOTFS_URL="$DEV_SERVER/$DEV_PATH/rootfs.squashfs"

echo "Updating configuration to use development ISO..."
echo ""
echo "Dev Server: $DEV_SERVER"
echo "Path: $DEV_PATH"
echo ""

# Update config.yaml using sed to preserve formatting
sed -i "s|^harvester_iso_url:.*|harvester_iso_url: $ISO_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_kernel_url:.*|harvester_kernel_url: $KERNEL_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_ramdisk_url:.*|harvester_ramdisk_url: $RAMDISK_URL|" "$CONFIG_FILE"
sed -i "s|^harvester_rootfs_url:.*|harvester_rootfs_url: $ROOTFS_URL|" "$CONFIG_FILE"

echo "Configuration updated successfully!"
echo ""
echo "Current settings:"
echo "  ISO:     $ISO_URL"
echo "  Kernel:  $KERNEL_URL"
echo "  Initrd:  $RAMDISK_URL"
echo "  Rootfs:  $ROOTFS_URL"
