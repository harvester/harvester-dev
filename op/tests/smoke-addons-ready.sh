#!/bin/bash -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
SMOKE_DIR=$(get_smoke_dir)
KUBECONFIG_FILE=$(get_kubeconfig_file)

if [ ! -f "$KUBECONFIG_FILE" ]; then
  echo "Error: kubeconfig file not found at $KUBECONFIG_FILE."
  exit 1
fi

# Prepare the addon test configuration.
addons_config="$TOP_DIR/state/addons_config.yaml"
rm -f "$addons_config"
cp "$SMOKE_DIR/addons_config.yaml.sample" "$addons_config"

echo "Running smoke test to enable and verify Harvester addons..."
set -x
cd "$SMOKE_DIR"
go test -v -count 1 -timeout 4h ./pkg/addons -run TestAddons \
  -addonsconfig "$addons_config" \
  -kubeconfig "$KUBECONFIG_FILE"
