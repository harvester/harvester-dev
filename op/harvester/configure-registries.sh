#!/bin/bash -eu
# Apply containerd-registry Setting to Harvester cluster from .harvester.registry_mirrors config
# (https://docs.harvesterhci.io/v1.8/advanced/index#containerd-registry)
#
# Config format (.harvester.registry_mirrors in config.yaml):
#   registry_mirrors:
#     - registry: docker.io
#       endpoint: http://10.8.0.101:5000
#     - registry: ghcr.io
#       endpoint: http://10.8.0.101:5004

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
CONFIG_FILE=$(get_config_file)
KUBECONFIG="${TOP_DIR}/kubeconfig"
KUBECTL="kubectl --kubeconfig ${KUBECONFIG}"

MIRROR_COUNT=$(yq -e '.harvester.registry_mirrors | length' "$CONFIG_FILE")

if [ "$MIRROR_COUNT" -eq 0 ]; then
  echo "No registry mirrors defined in .harvester.registry_mirrors — nothing to apply"
  exit 0
fi

echo "Building containerd-registry setting from $MIRROR_COUNT mirror(s)..."

# Build the Mirrors JSON object: { "<registry>": { "Endpoints": ["<endpoint>"], "Rewrites": null }, ... }
MIRRORS_JSON=$(yq -e '.harvester.registry_mirrors' "$CONFIG_FILE" -o=json | \
  jq 'reduce .[] as $m ({}; . + {($m.registry): {"Endpoints": [$m.endpoint], "Rewrites": null}})')

VALUE=$(jq -cn --argjson mirrors "$MIRRORS_JSON" \
  '{"Mirrors": $mirrors, "Configs": null, "Auths": null}')

echo "Applying containerd-registry setting:"
echo "$VALUE" | jq .

$KUBECTL apply -f - <<EOF
apiVersion: harvesterhci.io/v1beta1
kind: Setting
metadata:
  name: containerd-registry
value: '${VALUE}'
EOF

echo "containerd-registry setting applied successfully"
