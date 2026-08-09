#!/bin/bash -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
TOP_DIR=$(get_top_dir)
SMOKE_DIR=$(get_smoke_dir)
STATE_DIR=${TOP_DIR}/state

CONFIG=$(get_config_file)
KUBECONFIG_FILE=$(get_kubeconfig_file)

if [ ! -f "$KUBECONFIG_FILE" ]; then
  echo "Error: kubeconfig file not found at $KUBECONFIG_FILE."
  exit 1
fi

# get cluster test config according to branch
configured_branch=$(yq '.tests.cluster.branch // ""' "$CONFIG")
if [[ -n "$configured_branch" && "$configured_branch" != "null" ]]; then
    harvester_branch="$configured_branch"
    echo "Using Harvester branch override from config.yaml: $harvester_branch"
else
    VERSIONS_FILE="$STATE_DIR/versions.yaml"
    if [ ! -f "$VERSIONS_FILE" ]; then
        echo "Error: Versions file not found at $VERSIONS_FILE."
        exit 1
    fi
    harvester_branch=$(yq '.branch' "$VERSIONS_FILE")
    echo "Detected Harvester branch: $harvester_branch"
fi

test_config_file="cluster_config.yaml.sample"
if [ -z "$harvester_branch" ]; then
    echo "Harvester branch is empty. Using default: $test_config_file"
else
    branch_config_file="$SMOKE_DIR/cluster_config_${harvester_branch}.yaml.sample"
    if [ -f "$branch_config_file" ]; then
        test_config_file="cluster_config_${harvester_branch}.yaml.sample"
        echo "Using branch-specific cluster config: $test_config_file"
    else
        echo "$branch_config_file is not found. Using default: $test_config_file"
    fi
fi

# prepare config
cluster_config="$TOP_DIR/state/cluster_config.yaml"
rm -f "$cluster_config"
echo "Copying $SMOKE_DIR/$test_config_file to $cluster_config"
cp -f "$SMOKE_DIR/$test_config_file" "$cluster_config"

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
echo "Running smoke test to verify the cluster is ready..."
set -x
cd "$SMOKE_DIR"
go test -v -count 1 -timeout 4h ./pkg/cluster -run TestClusterReady \
  -clusterconfig $cluster_config \
  -kubeconfig $KUBECONFIG_FILE
