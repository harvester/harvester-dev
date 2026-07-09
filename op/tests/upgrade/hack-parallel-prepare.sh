#!/bin/bash -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../../lib.sh"
TOP_DIR=$(get_top_dir)

KUBECONFIG_FILE=$(get_kubeconfig_file)

if [ ! -f "$KUBECONFIG_FILE" ]; then
  echo "Error: kubeconfig file not found at $KUBECONFIG_FILE."
  exit 1
fi

ENABLE_PARALLEL_IMAGE_PRELOAD=$(yq eval '.tests.upgrade.parallel_preload' "$TOP_DIR/config.yaml")

if [ "$ENABLE_PARALLEL_IMAGE_PRELOAD" != "true" ]; then
  echo "Skipping parallel image preload (config is not 'true')"
  exit 0
fi

echo "Enable parallel image preload.."

export KUBECONFIG="$KUBECONFIG_FILE"
kubectl apply -f - <<'EOF'
apiVersion: harvesterhci.io/v1beta1
kind: Setting
metadata:
  name: upgrade-config
value: '{"imagePreloadOption":{"strategy":{"type":"parallel"}},"nodeUpgradeOption":{"strategy":{"mode":"auto"}},"restoreVM": false, "logReadyTimeout": "5"}'
EOF
