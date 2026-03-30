#!/bin/bash -e

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

CONFIG_FILE=$(get_config_file)

# Read prefix and node count from config.yaml using yq
PREFIX=$(yq '.provider.domain_prefix' "$CONFIG_FILE")

echo "Destroying Rancher node with prefix: $PREFIX"

NODE_NAME="${PREFIX}-rancher"
echo "Destroying ${NODE_NAME}..."
libvirt_destroy_domain "${NODE_NAME}"

echo "Rancher node is destroyed successfully."