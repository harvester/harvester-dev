#!/bin/bash -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
TOP_DIR=$(get_top_dir)

SSH_CONFIG="$TOP_DIR/state/ssh_config"
CONFIG=$(get_config_file)
KUBECONFIG_FILE=$(get_kubeconfig_file)

ip_type=$(yq '.harvester.kubeconfig_server_ip_type // "vip"' "$CONFIG")
case "$ip_type" in
  vip)
    server_ip=$(yq -e '.vip' "$CONFIG")
    ;;
  first_node)
    server_ip=$(yq -e '.nodes[0].ip' "$CONFIG")
    ;;
  *)
    echo "Unknown harvester.kubeconfig_server_ip_type: $ip_type" >&2
    exit 1
    ;;
esac

ssh -F "$SSH_CONFIG" node1 sudo cat /etc/rancher/rke2/rke2.yaml > "$KUBECONFIG_FILE"

sed -i "s,127.0.0.1:6443,$server_ip:6443," "$KUBECONFIG_FILE"

echo "RKE2 kubeconfig has been saved to $KUBECONFIG_FILE with server address set to $server_ip:6443"
echo "You can use this kubeconfig to access the RKE2 cluster. For example:"
echo "export KUBECONFIG=$KUBECONFIG_FILE"
