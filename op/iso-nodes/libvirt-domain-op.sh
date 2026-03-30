#!/bin/bash -eu

OP="$1"

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

CONFIG_FILE=$(get_config_file)

# Read prefix and node count from config.yaml using yq
PREFIX=$(yq '.provider.domain_prefix' "$CONFIG_FILE")

ENABLED_NODE_COUNT=$(yq '.iso_boot.count' "$CONFIG_FILE")

case "$OP" in
  start)
    for i in $(seq 1 $ENABLED_NODE_COUNT); do
        NODE_NAME="${PREFIX}-iso-node${i}"
        libvirt_start_domain "${NODE_NAME}"
    done
    ;;
  destroy)
    for i in $(seq 1 $ENABLED_NODE_COUNT); do
        NODE_NAME="${PREFIX}-iso-node${i}"
        libvirt_destroy_domain "${NODE_NAME}"
    done
    ;;
  shutdown)
    for i in $(seq 1 $ENABLED_NODE_COUNT); do
        NODE_NAME="${PREFIX}-iso-node${i}"
        libvirt_shutdown_domain "${NODE_NAME}"
    done
    ;;
  *)
    echo "Usage: $0 {start|destroy|shutdown}"
    exit 1
    ;;
esac
