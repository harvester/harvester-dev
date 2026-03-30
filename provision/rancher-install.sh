#!/bin/bash -e

# Source environment file if provided as first argument
ENV_FILE="${1:-}"
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    echo "Loading configuration from $ENV_FILE"
    source "$ENV_FILE"
fi

# Read from environment variables with defaults
INSTALL_K3S_VERSION="${K3S_VERSION:-v1.35.3+k3s1}"
RANCHER_REPO="${RANCHER_REPO:-https://releases.rancher.com/server-charts/latest}"
RANCHER_VERSION="${RANCHER_VERSION:-v2.13.4}"
RANCHER_BOOTSTRAP_PASSWORD="${RANCHER_BOOTSTRAP_PASSWORD:-password}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.10.8.0.5.sslip.io}"

echo "Starting Rancher provisioning with:"
echo "  K3S Version: $INSTALL_K3S_VERSION"
echo "  Rancher Version: $RANCHER_VERSION"
echo "  Rancher Hostname: $RANCHER_HOSTNAME"

STATE_DIR="/var/lib/harvester-dev"

check_state() {
    mkdir -p "${STATE_DIR}"
    local state_file="${STATE_DIR}/rancher_provisioned"

    if [ -f "${state_file}" ]; then
        local state=$(cat "${state_file}")
        echo "Rancher already provisioned with state: ${state}"
        if [ "${state}" = "failed" ]; then
            exit 1
        fi
        exit 0
    fi
}

mark_state() {
    local state="$1"
    local state_file="${STATE_DIR}/rancher_provisioned"

    if [ -e "${state_file}" ]; then
        echo "Error: State file already exists."
        exit 1
    fi

    echo "${state}" > "${state_file}"
}

# Error handler to mark state as failed on any error
error_handler() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "Error: Script failed with exit code $exit_code"
        mark_state "failed"
    fi
}

# Trap errors and call error handler
trap error_handler ERR EXIT

install_k3s() {
	curl -sfL https://get.k3s.io | sh -
}

setup_k3s_localrc() {

cat > /etc/bash.bashrc.local <<EOF
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
export PATH="${PATH}:/var/lib/rancher/k3s/data/current/bin"
if [ -z "$CONTAINER_RUNTIME_ENDPOINT" ]; then
    export CONTAINER_RUNTIME_ENDPOINT=unix:///var/run/k3s/containerd/containerd.sock
fi
if [ -z "$IMAGE_SERVICE_ENDPOINT" ]; then
    export IMAGE_SERVICE_ENDPOINT=unix:///var/run/k3s/containerd/containerd.sock
fi

# For ctr
if [ -z "$CONTAINERD_ADDRESS" ]; then
    export CONTAINERD_ADDRESS=/run/k3s/containerd/containerd.sock
fi
EOF


    echo '. /etc/bash.bashrc.local' >> ~/.bashrc
}


wait_for_k3s() {
    # trivial wait, assume one node
    echo "Waiting for k3s node to be ready..."
    
    local max_attempts=60
    local count=0
    
    while [ $count -lt $max_attempts ]; do
        status=$(kubectl get nodes | grep "^$(cat /etc/hostname)" | awk '{print $2}')
        if [ "$status" = "Ready" ]; then
            echo "k3s node is ready!"
            kubectl get nodes
            return 0
        else
            echo "k3s node not yet ready. Retrying in 5 seconds..."
            sleep 5
        fi
        count=$((count + 1))
    done
    
    echo "Error: k3s node did not become ready after 5 minutes"
    return 1
}

install_helm() {
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

install_k9s() {
    pushd /tmp > /dev/null
    curl -sL -O https://github.com/derailed/k9s/releases/download/v0.50.18/k9s_Linux_amd64.tar.gz
    tar xzvf k9s_Linux_amd64.tar.gz
    mv k9s /usr/bin
    popd > /dev/null
}

install_cert_manager() {
  # Install cert-manager using Helm
    helm repo add jetstack https://charts.jetstack.io
    helm repo update
    helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --set crds.enabled=true
}

install_rancher() {
    helm repo add rancher "${RANCHER_REPO}"
    helm repo update

    helm install rancher rancher/rancher \
        --namespace cattle-system \
        --create-namespace \
        --version "${RANCHER_VERSION}" \
        --set-string ingress.extraAnnotations.'nginx\.ingress\.kubernetes\.io/http2-push-preload'=false \
        --set bootstrapPassword="${RANCHER_BOOTSTRAP_PASSWORD}" \
        --set hostname="${RANCHER_HOSTNAME}" \
        --set replicas=1
}

wait_rancher_pods() {
    echo "Waiting for Rancher pods to be ready..."
    local max_attempts=60
    local count=0
    
    while [ $count -lt $max_attempts ]; do
        # Check if any pods exist first
        pod_count=$(kubectl get pods -n cattle-system -l app=rancher --no-headers 2>/dev/null | wc -l)
        if [ "$pod_count" -eq 0 ]; then
            echo "Rancher pods not yet created. Retrying in 10 seconds..."
            sleep 10
        else
            ready=$(kubectl get pods -n cattle-system -l app=rancher -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep false || true)
            if [ -z "$ready" ]; then
                echo "Rancher pods are ready!"
                kubectl get pods -n cattle-system -l app=rancher
                return 0
            else
                echo "Rancher pods not yet ready. Retrying in 10 seconds..."
                sleep 10
            fi
        fi
        count=$((count + 1))
    done
    
    echo "Error: Rancher pods did not become ready after 10 minutes"
    return 1
}

wait_rancher_webhook_pods() {
    echo "Waiting for Rancher webhook pods to be ready..."
    local max_attempts=60
    local count=0
    
    while [ $count -lt $max_attempts ]; do
        # Check if any pods exist first
        pod_count=$(kubectl get pods -n cattle-system -l app=rancher-webhook --no-headers 2>/dev/null | wc -l)
        if [ "$pod_count" -eq 0 ]; then
            echo "Rancher webhook pods not yet created. Retrying in 10 seconds..."
            sleep 10
        else
            ready=$(kubectl get pods -n cattle-system -l app=rancher-webhook -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep false || true)
            if [ -z "$ready" ]; then
                echo "Rancher webhook pods are ready!"
                kubectl get pods -n cattle-system -l app=rancher-webhook
                return 0
            else
                echo "Rancher webhook pods not yet ready. Retrying in 10 seconds..."
                sleep 10
            fi
        fi
        count=$((count + 1))
    done
    
    echo "Error: Rancher webhook pods did not become ready after 10 minutes"
    return 1
}

check_state

install_k3s
setup_k3s_localrc
. /etc/bash.bashrc.local

wait_for_k3s
install_helm
install_k9s
install_cert_manager
install_rancher
wait_rancher_pods
wait_rancher_webhook_pods

mark_state "provisioned"