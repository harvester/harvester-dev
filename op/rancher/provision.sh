#!/bin/bash -e

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
ssh_config="$TOP_DIR/state/ssh_config"
CONFIG_FILE=$(get_config_file)

PROVISION_SCRIPT="$TOP_DIR/provision/rancher-install.sh"
REMOTE_SCRIPT_PATH="/tmp/rancher-install.sh"
REMOTE_ENV_PATH="/tmp/rancher-install.env"
REMOTE_REGISTRIES_PATH="/tmp/rancher-registries.yaml"

# Read rancher configuration from config.yaml
K3S_VERSION=$(yq -e '.rancher.k3s_version' "$CONFIG_FILE")
RANCHER_REPO=$(yq -e '.rancher.repo' "$CONFIG_FILE")
RANCHER_VERSION=$(yq -e '.rancher.version' "$CONFIG_FILE")
RANCHER_BOOTSTRAP_PASSWORD=$(yq -e '.rancher.bootstrap_password' "$CONFIG_FILE")
RANCHER_HOSTNAME=$(yq -e '.rancher.hostname' "$CONFIG_FILE")

# Create temporary files
ENV_FILE=$(mktemp)
REGISTRIES_FILE=$(mktemp)
trap "rm -f $ENV_FILE $REGISTRIES_FILE" EXIT

# Build k3s registries.yaml from .rancher.registry_mirrors (optional), e.g.
#   registry_mirrors:
#     - registry: docker.io
#       endpoint: http://10.0.10.1:5000
MIRROR_COUNT=$(yq '.rancher.registry_mirrors // [] | length' "$CONFIG_FILE")
K3S_REGISTRIES_FILE=""
if [ "$MIRROR_COUNT" -gt 0 ]; then
  yq -o=json '.rancher.registry_mirrors' "$CONFIG_FILE" | \
    jq '{mirrors: (reduce .[] as $m ({}; . + {($m.registry): {endpoint: [$m.endpoint]}}))}' | \
    yq -P > "$REGISTRIES_FILE"
  K3S_REGISTRIES_FILE="$REMOTE_REGISTRIES_PATH"
fi

cat > "$ENV_FILE" <<EOF
# Rancher provisioning configuration
export K3S_VERSION="$K3S_VERSION"
export RANCHER_REPO="$RANCHER_REPO"
export RANCHER_VERSION="$RANCHER_VERSION"
export RANCHER_BOOTSTRAP_PASSWORD="$RANCHER_BOOTSTRAP_PASSWORD"
export RANCHER_HOSTNAME="$RANCHER_HOSTNAME"
export K3S_REGISTRIES_FILE="$K3S_REGISTRIES_FILE"
EOF

if [ -n "$K3S_REGISTRIES_FILE" ]; then
  echo "Uploading k3s registries.yaml to rancher VM..."
  cat "$REGISTRIES_FILE"
  ssh_upload rancher "$REGISTRIES_FILE" "$REMOTE_REGISTRIES_PATH"
fi

echo "Uploading environment file to rancher VM..."
ssh_upload rancher "$ENV_FILE" "$REMOTE_ENV_PATH"

echo "Uploading provisioning script to rancher VM..."
ssh_upload rancher "$PROVISION_SCRIPT" "$REMOTE_SCRIPT_PATH"

echo "Making the script executable..."
ssh_exec rancher "chmod +x $REMOTE_SCRIPT_PATH"

echo "Executing provisioning script on rancher VM with configuration:"
echo "  K3S Version: $K3S_VERSION"
echo "  Rancher Version: $RANCHER_VERSION"
echo "  Rancher Hostname: $RANCHER_HOSTNAME"
ssh_exec rancher "sudo $REMOTE_SCRIPT_PATH $REMOTE_ENV_PATH"

echo "Rancher provisioning completed successfully!"