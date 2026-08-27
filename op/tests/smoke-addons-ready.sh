#!/bin/bash -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

if [ "$#" -gt 1 ]; then
  echo "Usage: $(basename "$0") [ADDON]" >&2
  exit 1
fi

addon_name="${1:-}"

TOP_DIR=$(get_top_dir)
SMOKE_DIR=$(get_smoke_dir)
CONFIG=$(get_config_file)
KUBECONFIG_FILE=$(get_kubeconfig_file)

if [ ! -f "$KUBECONFIG_FILE" ]; then
  echo "Error: kubeconfig file not found at $KUBECONFIG_FILE."
  exit 1
fi

# Prepare the addon test configuration.
addons_config="$TOP_DIR/state/addons_config.yaml"
rm -f "$addons_config"
cp "$SMOKE_DIR/addons_config.yaml.sample" "$addons_config"

NODE_COUNT=$(yq '.node_count' "$CONFIG")
if [ "$NODE_COUNT" -lt 2 ]; then
  echo "Removing descheduler from the addon test configuration because node_count is less than 2"
  yq -i 'del(.addons[] | select(.namespace == "kube-system" and .name == "descheduler"))' "$addons_config"
fi

if [ -n "$addon_name" ]; then
  ADDON_NAME="$addon_name" yq -i '.addons = [.addons[] | select(.name == strenv(ADDON_NAME))]' "$addons_config"

  if [ "$(yq '.addons | length' "$addons_config")" -eq 0 ]; then
    echo "Error: addon '$addon_name' is not available in the addon test configuration." >&2
    exit 1
  fi

  echo "Running smoke test for Harvester addon $addon_name..."
else
  echo "Running smoke test for all configured Harvester addons..."
fi

set -x
cd "$SMOKE_DIR"
go test -v -count 1 -timeout 4h ./pkg/addons -run TestAddons \
  -addonsconfig "$addons_config" \
  -kubeconfig "$KUBECONFIG_FILE"
