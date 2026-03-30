#!/bin/bash -eu
# Create guest clusters

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
CONFIG_FILE=$(get_config_file)
STATE_DIR=${TOP_DIR}/state
RANCHER_KUBECONFIG=${STATE_DIR}/rancher_bootstrap_kubeconfig
RANCHER_BOOTSTRAP_CREDENTIALS=${STATE_DIR}/rancher_bootstrap_credentials.yaml

KUBECTL="kubectl --kubeconfig ${RANCHER_KUBECONFIG}"

# Read configuration from config.yaml
HARVESTER_CLUSTER_NAME=$(yq -e '.harvester.name' "$CONFIG_FILE")

API_URL=$(yq -e '.api_url' "$RANCHER_BOOTSTRAP_CREDENTIALS")
ADMIN_TOKEN_KEY=$(yq -e '.admin_token_key' "$RANCHER_BOOTSTRAP_CREDENTIALS")

if [ -z "$API_URL" ] || [ -z "$ADMIN_TOKEN_KEY" ]; then
    echo "Error: API URL or Admin Token Key is missing in ${RANCHER_BOOTSTRAP_CREDENTIALS}"
    exit 1
fi

create_cloud_provider_kubeconfig() {
    local guest_cluster_namespace="$1"
    local guest_cluster_name="$2"

    local provisionig_cluster_name=$($KUBECTL get clusters.provisioning.cattle.io -n fleet-default $HARVESTER_CLUSTER_NAME -o yaml | yq .status.clusterName)

    if [ -z "$provisionig_cluster_name" ] || [ "$provisionig_cluster_name" == "null" ]; then
        echo "Error: Provisioning cluster name is not available for Harvester cluster $HARVESTER_CLUSTER_NAME"
        exit 1
    fi

    echo "Creating kubeconfig for cloud provider with provisioning cluster name: ${provisionig_cluster_name}"
    local payload=$(jq -n --arg cluster_name "$guest_cluster_name" \
                    --arg namespace "$guest_cluster_namespace" \
                   '{"clusterRoleName": "harvesterhci.io:cloudprovider", "namespace": $namespace, "serviceAccountName": $cluster_name}' )

    local save_to="${STATE_DIR}/${guest_cluster_name}_cloud_provider_kubeconfig.yaml"

    # seems to be ok to recreate
    if ! curl -fsSk -X POST "$API_URL/k8s/clusters/$provisionig_cluster_name/v1/harvester/kubeconfig" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $ADMIN_TOKEN_KEY" \
        -d "$payload" | xargs | sed 's/\\n/\n/g' > "$save_to"; then
        echo "Error: Failed to create cloud provider kubeconfig for $guest_cluster_name"
        exit 1
    fi

    if [ -z "$(cat $save_to)" ]; then
        echo "Error: $save_to is empty"
        exit 1
    fi

    echo "Kubeconfig for cloud provider saved to $save_to"
}

create_guest_clusters() {
    pushd "$SCRIPT_DIR/guest-cluster" > /dev/null
    terraform init
    terraform apply --auto-approve
    popd > /dev/null
}

GUEST_CLUSTER_COUNT=$(yq -e '.guest_clusters | length' "$CONFIG_FILE")

if [ "$GUEST_CLUSTER_COUNT" -eq 0 ]; then
    echo "No guest clusters defined in configuration"
    exit 0
fi

echo "Found $GUEST_CLUSTER_COUNT guest cluster(s) to create"

for i in $(seq 0 $((GUEST_CLUSTER_COUNT - 1))); do
    echo "Processing guest cluster $((i + 1))/$GUEST_CLUSTER_COUNT..."
    
    GUEST_CLUSTER_NAME=$(yq -e ".guest_clusters[$i].name" "$CONFIG_FILE")
    GUEST_CLUSTER_NAMESPACE=$(yq -e ".guest_clusters[$i].namespace" "$CONFIG_FILE")
    
    echo "  Name: $GUEST_CLUSTER_NAME"
    echo "  Namespace: $GUEST_CLUSTER_NAMESPACE"
    create_cloud_provider_kubeconfig "$GUEST_CLUSTER_NAMESPACE" "$GUEST_CLUSTER_NAME"
done

create_guest_clusters

echo "All guest clusters processed successfully"

