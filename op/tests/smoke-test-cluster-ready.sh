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

# prepare config
cluster_config="$TOP_DIR/state/cluster_config.yaml"
rm -f "$cluster_config"
cp "$SMOKE_TEST_DIR/cluster_config.yaml.sample" "$cluster_config"

# Update cluster config with values from config.yaml
VIP=$(yq '.vip' "$CONFIG")
NODE_COUNT=$(yq '.node_count' "$CONFIG")

# Calculate controller and etcd counts based on node count
if [ "$NODE_COUNT" -ge 3 ]; then
  CONTROLLER_COUNT=3
  ETCD_COUNT=3
else
  CONTROLLER_COUNT=1
  ETCD_COUNT=1
fi

# Update the cluster config file
yq -i ".vip = \"$VIP\"" "$cluster_config"
yq -i ".nodeCount = $NODE_COUNT" "$cluster_config"
yq -i ".controllerCount = $CONTROLLER_COUNT" "$cluster_config"
yq -i ".etcdCount = $ETCD_COUNT" "$cluster_config"

echo "Updated cluster config with: VIP=$VIP, nodeCount=$NODE_COUNT, controllerCount=$CONTROLLER_COUNT, etcdCount=$ETCD_COUNT"

# Run the smoke test
echo "Running smoke tests to verify the cluster is ready..."
set -x
cd "$SMOKE_TEST_DIR"
go test -v -count 1 -timeout 4h ./pkg/cluster -run TestClusterReady \
  -clusterconfig $cluster_config \
  -kubeconfig $KUBECONFIG
