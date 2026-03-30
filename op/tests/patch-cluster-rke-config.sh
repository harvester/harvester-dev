#!/bin/bash -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
TOP_DIR=$(get_top_dir)

KUBECONFIG=${KUBECONFIG:-"$TOP_DIR/kubeconfig"}
CLUSTER_NAME=${CLUSTER_NAME:-"local"}
CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE:-"fleet-local"}

if [ ! -f "$KUBECONFIG" ]; then
  echo "Error: kubeconfig file not found at $KUBECONFIG."
  exit 1
fi

export KUBECONFIG

echo "Fetching current provisionGeneration..."
CURRENT_PROVISION_GEN=$(kubectl get cluster.provisioning.cattle.io "$CLUSTER_NAME" -n "$CLUSTER_NAMESPACE" -o jsonpath='{.spec.rkeConfig.provisionGeneration}')

if [ -z "$CURRENT_PROVISION_GEN" ]; then
  echo "Error: Could not retrieve current provisionGeneration"
  exit 1
fi

NEW_PROVISION_GEN=$((CURRENT_PROVISION_GEN + 1))
echo "Current provisionGeneration: $CURRENT_PROVISION_GEN"
echo "New provisionGeneration: $NEW_PROVISION_GEN"

# Create patch file
PATCH_FILE=$(mktemp)
trap "rm -f $PATCH_FILE" EXIT

cat > "$PATCH_FILE" <<EOF
spec:
  rkeConfig:
    chartValues: null
    dataDirectories: {}
    machineGlobalConfig: null
    machinePoolDefaults: {}
    provisionGeneration: $NEW_PROVISION_GEN
    upgradeStrategy:
      controlPlaneDrainOptions:
        deleteEmptyDirData: true
        disableEviction: false
        enabled: true
        force: true
        gracePeriod: 0
        ignoreDaemonSets: true
        skipWaitForDeleteTimeoutSeconds: 0
        timeout: 0
        preDrainHooks:
        - annotation: harvesterhci.io/pre-hook
        postDrainHooks:
        - annotation: harvesterhci.io/post-hook
      workerDrainOptions:
        deleteEmptyDirData: true
        disableEviction: false
        enabled: true
        force: false
        gracePeriod: 0
        ignoreDaemonSets: true
        skipWaitForDeleteTimeoutSeconds: 0
        timeout: 0
        preDrainHooks:
        - annotation: harvesterhci.io/pre-hook
        postDrainHooks:
        - annotation: harvesterhci.io/post-hook
EOF

echo "Applying patch to cluster $CLUSTER_NAME in namespace $CLUSTER_NAMESPACE..."
kubectl patch cluster.provisioning.cattle.io "$CLUSTER_NAME" -n "$CLUSTER_NAMESPACE" --type=merge --patch-file="$PATCH_FILE"

echo "Patch applied successfully!"
echo "Verifying the updated provisionGeneration..."
UPDATED_PROVISION_GEN=$(kubectl get cluster.provisioning.cattle.io "$CLUSTER_NAME" -n "$CLUSTER_NAMESPACE" -o jsonpath='{.spec.rkeConfig.provisionGeneration}')
echo "Updated provisionGeneration: $UPDATED_PROVISION_GEN"
