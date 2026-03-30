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

# Read rancher configuration from config.yaml
K3S_VERSION=$(yq -e '.rancher.k3s_version' "$CONFIG_FILE")
RANCHER_REPO=$(yq -e '.rancher.repo' "$CONFIG_FILE")
RANCHER_VERSION=$(yq -e '.rancher.version' "$CONFIG_FILE")
RANCHER_BOOTSTRAP_PASSWORD=$(yq -e '.rancher.bootstrap_password' "$CONFIG_FILE")
RANCHER_HOSTNAME=$(yq -e '.rancher.hostname' "$CONFIG_FILE")

# Create temporary environment file
ENV_FILE=$(mktemp)
trap "rm -f $ENV_FILE" EXIT

cat > "$ENV_FILE" <<EOF
# Rancher provisioning configuration
export K3S_VERSION="$K3S_VERSION"
export RANCHER_REPO="$RANCHER_REPO"
export RANCHER_VERSION="$RANCHER_VERSION"
export RANCHER_BOOTSTRAP_PASSWORD="$RANCHER_BOOTSTRAP_PASSWORD"
export RANCHER_HOSTNAME="$RANCHER_HOSTNAME"
EOF

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