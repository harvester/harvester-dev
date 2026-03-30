#!/bin/bash -eu

state="$1"

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

CONFIG_FILE=$(get_config_file)

# Read prefix and node count from config.yaml using yq
PREFIX=$(yq '.provider.domain_prefix' "$CONFIG_FILE")

echo "Modifying Rancher node state with prefix: $PREFIX"
NODE_NAME="${PREFIX}-rancher"

if [ "$state" == "on" ]; then
    echo "Starting ${NODE_NAME}..."
    libvirt_start_domain "${NODE_NAME}"
elif [ "$state" == "off" ]; then
    echo "Shutting down ${NODE_NAME}..."
    libvirt_shutdown_domain "${NODE_NAME}"
else
    echo "Invalid state: $state. Use 'on' or 'off'."
    exit 1
fi

echo "Rancher node is set to ${state} successfully."
