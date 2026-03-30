#!/bin/bash -eu
# Select an ISO and update config file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.yaml"
ISOS_DIR="$SCRIPT_DIR/isos"

# Get artifact server URL from config
ARTIFACT_SERVER_URL=$(yq -e '.artifact_server_url' "$CONFIG_FILE")

echo "Available Harvester versions:"
echo ""

# List available ISO directories with numbers
versions=()
index=1
for dir in "$ISOS_DIR"/*/; do
  if [ -d "$dir" ]; then
    version=$(basename "$dir")
    versions+=("$version")
    echo "  $index) $version"
    ((index++))
  fi
done

echo ""

# Get selection
if [ $# -eq 1 ]; then
  selection="$1"
else
  read -p "Select version [1-${#versions[@]}] (default: 1): " selection
  selection=${selection:-1}
fi

# Validate numeric selection
if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#versions[@]}" ]; then
  echo "Error: Invalid selection. Please choose a number between 1 and ${#versions[@]}"
  exit 1
fi

# Get selected version (arrays are 0-indexed)
SELECTED_VERSION="${versions[$((selection - 1))]}"

echo "Selected version: $SELECTED_VERSION"
echo "Updating config.yaml..."

# Update config.yaml using sed to preserve formatting
sed -i "s|^harvester_version:.*|harvester_version: $SELECTED_VERSION|" "$CONFIG_FILE"
sed -i "s|^harvester_iso_url:.*|harvester_iso_url: $ARTIFACT_SERVER_URL/isos/$SELECTED_VERSION/$SELECTED_VERSION-amd64.iso|" "$CONFIG_FILE"
sed -i "s|^harvester_kernel_url:.*|harvester_kernel_url: $ARTIFACT_SERVER_URL/isos/$SELECTED_VERSION/$SELECTED_VERSION-vmlinuz-amd64|" "$CONFIG_FILE"
sed -i "s|^harvester_ramdisk_url:.*|harvester_ramdisk_url: $ARTIFACT_SERVER_URL/isos/$SELECTED_VERSION/$SELECTED_VERSION-initrd-amd64|" "$CONFIG_FILE"
sed -i "s|^harvester_rootfs_url:.*|harvester_rootfs_url: $ARTIFACT_SERVER_URL/isos/$SELECTED_VERSION/$SELECTED_VERSION-rootfs-amd64.squashfs|" "$CONFIG_FILE"

echo "Configuration updated successfully!"
echo ""
echo "Current settings:"
echo "  ISO: $(yq '.harvester_iso_url' "$CONFIG_FILE")"
echo "  Kernel: $(yq '.harvester_kernel_url' "$CONFIG_FILE")"
echo "  Initrd: $(yq '.harvester_ramdisk_url' "$CONFIG_FILE")"
echo "  Rootfs: $(yq '.harvester_rootfs_url' "$CONFIG_FILE")"
