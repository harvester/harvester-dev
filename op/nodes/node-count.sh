#!/bin/bash -e

# Get or set node_count in config.yaml.
# Usage: node-count.sh [COUNT]
#   No argument: print the current node_count.
#   COUNT given: validate it's a positive integer and update config.yaml.

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

CONFIG_FILE=$(get_config_file)
COUNT="${1:-}"

if [[ -z "$COUNT" ]]; then
  yq '.node_count' "$CONFIG_FILE"
else
  [[ "$COUNT" =~ ^[1-9][0-9]*$ ]] || die "node count must be a positive integer: $COUNT"
  yq -i ".node_count = ${COUNT}" "$CONFIG_FILE"
  echo "node_count set to ${COUNT}"
fi
