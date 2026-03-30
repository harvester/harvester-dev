#!/bin/bash -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
TOP_DIR=$(get_top_dir)
SMOKE_TEST_DIR=$(get_smoke_tests_dir)

CONFIG=${CONFIG:-$(get_config_file)}
KUBECONFIG=${KUBECONFIG:-"$TOP_DIR/kubeconfig"}

if [ ! -f "$KUBECONFIG" ]; then
  echo "Error: kubeconfig file not found at $KUBECONFIG."
  exit 1
fi

# prepare upgrade config
upgrade_config="$TOP_DIR/state/upgrade_config.yaml"
rm -f "$upgrade_config"
cp "$SMOKE_TEST_DIR/upgrade_config.yaml.sample" "$upgrade_config"

UPGRADE_ISO_URL=$(yq '.tests.upgrade.iso_url' "$CONFIG")
NODE_COUNT=$(yq '.node_count' "$CONFIG")
yq -i ".upgradeISOURL = \"$UPGRADE_ISO_URL\"" "$upgrade_config"
yq -i ".nodeCount = $NODE_COUNT" "$upgrade_config"

echo "Run smoke tests to verify the cluster can be upgraded successfully..."
echo "Upgrade ISO URL: $UPGRADE_ISO_URL"


# hacks
# 1. increase CDI memory limit to avoid OOM issue during upgrade test
$SCRIPT_DIR/upgrade/hack-increase-cdi-limit.sh "2G"
# 2. parallel preload images
$SCRIPT_DIR/upgrade/hack-parallel-prepare.sh

set -x
cd "$SMOKE_TEST_DIR"
go test -v -count 1 -timeout 4h ./pkg/upgrade -run TestHarvesterUpgrade \
  -upgradeconfig $upgrade_config \
  -kubeconfig $KUBECONFIG
