#!/bin/bash -e
# Import Harvester cluster to Rancher

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
CONFIG_FILE=$(get_config_file)
STATE_DIR=${TOP_DIR}/state
RANCHER_KUBECONFIG=${STATE_DIR}/rancher_bootstrap_kubeconfig

KUBECTL="kubectl --kubeconfig ${RANCHER_KUBECONFIG}"

# Read configuration from config.yaml
HARVESTER_CLUSTER_NAME=$(yq -e '.harvester.name' "$CONFIG_FILE")


get_cluster_name() {
  local cluster_name_var="$1"
  $KUBECTL get clusters.provisioning.cattle.io -n fleet-default $cluster_name_var -o yaml 2>/dev/null | yq .status.clusterName
}

wait_for_cluster_name() {
  local cluster_name_var="$1"
  
  echo "Waiting for cluster name to be populated..."
  local max_attempts=24  # 2 minutes (24 * 5 seconds)
  local count=0
  
  while [ $count -lt $max_attempts ]; do
    local cluster_name=$($KUBECTL get clusters.provisioning.cattle.io -n fleet-default $cluster_name_var -o yaml 2>/dev/null | yq .status.clusterName)
    
    if [ -n "$cluster_name" ] && [ "$cluster_name" != "null" ]; then
      echo "Get clustername: $cluster_name"
      return 0
    fi
    
    echo "Cluster name not yet available (attempt $((count + 1))/$max_attempts)..."
    sleep 5
    count=$((count + 1))
  done
  
  echo "Error: Cluster name was not populated after 2 minutes"
  return 1
}


get_registration_import_cmd() {
  local cluster_name="$1"
  local insecure_command
  insecure_command=$($KUBECTL get clusterregistrationtokens.management.cattle.io -n $cluster_name default-token -o yaml 2>/dev/null | yq -r .status.insecureCommand)

  # in newer Rancher (>= v2.15.0 time, including some patch releases to older minor versions))
  # the insecureCommand now contains the placeholder '{token}' instead of the actual token, so we need to replace it with the actual token
  # example of the insecureCommand: 'curl --insecure -sfL https://rancher.10.0.8.5.sslip.io/v3/import/{token}_c-m-pqd24nj8.yaml | kubectl apply -f -'
  if [[ "$insecure_command" == *"{token}"* ]]; then
    local namespace="$cluster_name"
    local secret_name
    secret_name=$($KUBECTL -n "$namespace" get clusterregistrationtokens.management.cattle.io default-token \
      -o jsonpath='{.status.tokenSecretName}')
    local token
    token=$($KUBECTL -n "$namespace" get secret "$secret_name" \
      -o jsonpath='{.data.token}' | base64 --decode)
    insecure_command="${insecure_command//\{token\}/$token}"
  fi

  echo "$insecure_command"
}

wait_for_registration_token() {
  local cluster_name="$1"
  
  echo "Waiting for registration token to be created..."
  local max_attempts=24  # 2 minutes (24 * 5 seconds)
  local count=0
  
  until $KUBECTL get clusterregistrationtokens.management.cattle.io -n $cluster_name default-token &>/dev/null;
  do
    if [ $count -ge $max_attempts ]; then
      echo "Error: Registration token was not created after 2 minutes"
      return 1
    fi
    echo "Waiting for registration token to be created (attempt $((count + 1))/$max_attempts)..."
    sleep 5
    count=$((count + 1))
  done
  
  echo "Registration token created successfully!"
}

wait_for_harvester_imported() {
  local cluster_name="$1"
  
  echo "Waiting for Harvester cluster to be imported into Rancher..."
  local max_attempts=60  # 5 minutes (60 * 5 seconds)
  local count=0
  
  while [ $count -lt $max_attempts ]; do
    local ready=$($KUBECTL get clusters.provisioning.cattle.io -n fleet-default $cluster_name -o yaml 2>/dev/null | yq .status.ready)
    
    if [ -n "$ready" ] && echo "$ready" | grep -q "true"; then
      echo "Harvester cluster has been successfully imported into Rancher!"
      return 0
    fi
    
    echo "Harvester cluster ready status: $ready"
    echo "Harvester cluster not yet imported (attempt $((count + 1))/$max_attempts)..."
    sleep 5
    count=$((count + 1))
  done
  
  echo "Error: Harvester cluster was not imported after 5 minutes"
  return 1
}

import_harvester() {
  KUBECTL="kubectl --kubeconfig ${RANCHER_KUBECONFIG}"

  # TODO: this check is too trivial, maybe use agent uuid to check
  if $KUBECTL get clusters.provisioning.cattle.io -n fleet-default $HARVESTER_CLUSTER_NAME &>/dev/null; then
    echo "Harvester cluster already exists in Rancher"
    return 0
  fi

  cat <<EOF | $KUBECTL apply -f -
apiVersion: provisioning.cattle.io/v1
kind: Cluster
metadata:
  labels:
    provider.cattle.io: harvester
  name: $HARVESTER_CLUSTER_NAME
  namespace: fleet-default
spec:
  localClusterAuthEndpoint: {}
EOF

  wait_for_cluster_name "$HARVESTER_CLUSTER_NAME"
  if [ $? -ne 0 ]; then
    echo "Failed to get cluster name"
    return 1
  fi
  local cluster_name=$(get_cluster_name "$HARVESTER_CLUSTER_NAME")

  wait_for_registration_token "$cluster_name"
  if [ $? -ne 0 ]; then
    echo "Failed to get registration token"
    return 1
  fi
  local insecure_command=$(get_registration_import_cmd "$cluster_name")
  if [ -z "$insecure_command" ]; then
    echo "Error: insecureCommand is empty"
    exit 1
  fi
  echo "Import command: $insecure_command"

  bash -c "export KUBECONFIG=${TOP_DIR}/kubeconfig; $insecure_command"

  wait_for_harvester_imported "$HARVESTER_CLUSTER_NAME"
}

import_harvester
