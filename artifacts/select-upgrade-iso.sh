#!/bin/bash -eu
# Select an ISO and update config file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.yaml"
ISOS_DIR="$SCRIPT_DIR/isos"

# Get artifact server URL from config
ARTIFACT_SERVER_URL=$(yq -e '.artifact_server_url' "$CONFIG_FILE")

# List available ISO directories
versions=()
for dir in "$ISOS_DIR"/*/; do
  if [ -d "$dir" ]; then
    versions+=("$(basename "$dir")")
  fi
done

# Get selection
if [ $# -eq 1 ]; then
  SELECTED_VERSION="$1"

  # Validate that the given version is one of the available ISO directories
  valid=false
  for v in "${versions[@]}"; do
    if [ "$v" = "$SELECTED_VERSION" ]; then
      valid=true
      break
    fi
  done
  if [ "$valid" != true ]; then
    echo "Error: '$SELECTED_VERSION' is not a valid version. Available versions:"
    printf '  %s\n' "${versions[@]}"
    exit 1
  fi
else
  echo "Available Harvester versions:"
  echo ""
  index=1
  for version in "${versions[@]}"; do
    echo "  $index) $version"
    ((index++))
  done
  echo ""

  read -p "Select version [1-${#versions[@]}] (default: 1): " selection
  selection=${selection:-1}

  # Validate numeric selection
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#versions[@]}" ]; then
    echo "Error: Invalid selection. Please choose a number between 1 and ${#versions[@]}"
    exit 1
  fi

  # Get selected version (arrays are 0-indexed)
  SELECTED_VERSION="${versions[$((selection - 1))]}"
fi

echo "Selected version: $SELECTED_VERSION"
echo "Updating config.yaml..."

# Update config.yaml using sed to preserve formatting
yq -e -i ".tests.upgrade.iso_url = \"$ARTIFACT_SERVER_URL/isos/$SELECTED_VERSION/$SELECTED_VERSION-amd64.iso\"" "$CONFIG_FILE"

echo "Configuration updated successfully!"
echo ""
echo "Current settings:"
echo "  ISO: $(yq '.tests.upgrade.iso_url' "$CONFIG_FILE")"