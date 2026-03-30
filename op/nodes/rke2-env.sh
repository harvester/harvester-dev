#!/bin/bash -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
TOP_DIR=$(get_top_dir)

SSH_CONFIG="$TOP_DIR/state/ssh_config"
CONFIG=${CONFIG:-$(get_config_file)}
KUBECONFIG=${KUBECONFIG:-"$TOP_DIR/kubeconfig"}

vip=$(yq -e '.vip' "$CONFIG")

ssh -F "$SSH_CONFIG" node1 sudo cat /etc/rancher/rke2/rke2.yaml > "$KUBECONFIG"

sed -i "s,127.0.0.1:6443,$vip:6443," "$KUBECONFIG"

echo "RKE2 kubeconfig has been saved to $KUBECONFIG with server address set to $vip:6443"
echo "You can use this kubeconfig to access the RKE2 cluster. For example:"
echo "export KUBECONFIG=$KUBECONFIG"
