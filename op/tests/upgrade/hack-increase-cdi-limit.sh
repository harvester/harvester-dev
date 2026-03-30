#!/bin/bash -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../../lib.sh"
TOP_DIR=$(get_top_dir)

KUBECONFIG=${KUBECONFIG:-"$TOP_DIR/kubeconfig"}

if [ ! -f "$KUBECONFIG" ]; then
  echo "Error: kubeconfig file not found at $KUBECONFIG."
  exit 1
fi

MEMORY_LIMIT="${1:-2G}"

echo "Patching CDI resource to set podResourceRequirements.limits.memory=${MEMORY_LIMIT} ..."

kubectl --kubeconfig="$KUBECONFIG" patch cdi cdi --type=merge -p \
  "{\"spec\":{\"config\":{\"podResourceRequirements\":{\"limits\":{\"memory\":\"${MEMORY_LIMIT}\"}}}}}"

echo "Done. Current spec.config:"
kubectl --kubeconfig="$KUBECONFIG" get cdi cdi -o jsonpath='{.spec.config}' | jq

