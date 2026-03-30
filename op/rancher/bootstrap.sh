#!/bin/bash -e
# Bootstrap Rancher server

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
STATE_DIR=${TOP_DIR}/state

LOCAL_BOOTSTRAP_KUBECONFIG=${STATE_DIR}/rancher_bootstrap_kubeconfig
RANCHER_BOOTSTRAP_CREDENTIALS=${STATE_DIR}/rancher_bootstrap_credentials.yaml


rancher_bootstrap() {
    pushd $SCRIPT_DIR > /dev/null
    terraform -chdir=bootstrap apply --auto-approve
}

rancher_bootstrap_post() {
    pushd $SCRIPT_DIR > /dev/null

    terraform -chdir=bootstrap-post apply --auto-approve

    local kubeconfig_content=$(terraform -chdir=bootstrap-post output -json | jq -r .local_kubeconfig.value)
    if [ -z "$kubeconfig_content" ]; then
        echo "Error: local_kubeconfig output is empty. Please check the Terraform output for details."
        exit 1
    fi

    echo "$kubeconfig_content" > ${LOCAL_BOOTSTRAP_KUBECONFIG}
    echo "Writing Rancher local kubeconfig to ${LOCAL_BOOTSTRAP_KUBECONFIG}"
}

save_credentials() {
    local admin_password
    local bootstrap_token

    pushd $SCRIPT_DIR > /dev/null
    api_url=$(terraform -chdir=bootstrap output -json | jq -r .api_url.value)
    admin_token_key=$(terraform -chdir=bootstrap output -json | jq -r .admin_token_key.value)

    echo "Saving Rancher credentials to ${RANCHER_BOOTSTRAP_CREDENTIALS}"
    cat > ${RANCHER_BOOTSTRAP_CREDENTIALS} <<EOF
api_url: $api_url
admin_token_key: $admin_token_key
EOF
}

rancher_bootstrap
save_credentials
rancher_bootstrap_post
