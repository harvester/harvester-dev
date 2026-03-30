#!/bin/bash -eu

OP="$1"

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

CONFIG_FILE=$(get_config_file)

# Read prefix and node count from config.yaml using yq
PREFIX=$(yq '.provider.domain_prefix' "$CONFIG_FILE")

ENABLED_NODE_COUNT=$(yq '.node_count' "$CONFIG_FILE")

# Do snapshot operations on all nodes, not just enabled one
# This prevents some stale unclean snapshots
NODE_COUNT=$(yq '.nodes | length' "$CONFIG_FILE")

case "$OP" in
  start)
    for i in $(seq 1 $ENABLED_NODE_COUNT); do
        NODE_NAME="${PREFIX}-node${i}"
        libvirt_start_domain "${NODE_NAME}"
    done
    ;;
  destroy)
    for i in $(seq 1 $ENABLED_NODE_COUNT); do
        NODE_NAME="${PREFIX}-node${i}"
        libvirt_destroy_domain "${NODE_NAME}"
    done
    ;;
  shutdown)
    for i in $(seq 1 $ENABLED_NODE_COUNT); do
        NODE_NAME="${PREFIX}-node${i}"
        libvirt_shutdown_domain "${NODE_NAME}"
    done
    ;;
  snapshot)
    SNAPSHOT_NAME=$2
    if [ -z "$SNAPSHOT_NAME" ]; then
      echo "Error: Snapshot name is required for snapshot operation."
      echo "Usage: $0 snapshot <snapshot_name>"
      exit 1
    fi

    for i in $(seq 1 $NODE_COUNT); do
        NODE_NAME="${PREFIX}-node${i}"
        libvirt_snapshot_domain "${NODE_NAME}" "${SNAPSHOT_NAME}"
    done
    ;;
  snapshot-list)
    for i in $(seq 1 $NODE_COUNT); do
        NODE_NAME="${PREFIX}-node${i}"
        echo "Snapshots for ${NODE_NAME}:"
        libvirt_list_snapshots "${NODE_NAME}"
        echo ""
    done
    ;;
  snapshot-revert)
    SNAPSHOT_NAME=$2
    if [ -z "$SNAPSHOT_NAME" ]; then
      echo "Error: Snapshot name is required for snapshot-revert operation."
      echo "Usage: $0 snapshot-revert <snapshot_name>"
      exit 1
    fi

    for i in $(seq 1 $NODE_COUNT); do
        NODE_NAME="${PREFIX}-node${i}"
        libvirt_revert_snapshot "${NODE_NAME}" "${SNAPSHOT_NAME}"
    done
    ;;
  snapshot-clean)
    for i in $(seq 1 $NODE_COUNT); do
        NODE_NAME="${PREFIX}-node${i}"
        libvirt_delete_all_snapshots "${NODE_NAME}"
    done
    ;;
  *)
    echo "Usage: $0 {start|destroy|snapshot}"
    exit 1
    ;;
esac


