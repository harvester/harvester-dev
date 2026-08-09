#!/usr/bin/env bash
# Detect the Harvester release branch of a running cluster and write it to a
# yaml file (as .branch), so the probing steps can log freely to stdout
# instead of using stdout as the return channel.
# Usage: get-versions.sh <output-yaml-file>
#
# Detection order (first hit wins):
#   1. Harvester server-version setting (e.g. v1.6.1 -> v1.6)
#   2. First node's osImage (e.g. v1.6.1 -> v1.6)
#   3. node1's /etc/os-release VARIANT_ID (e.g. Harvester-v1.9-20260805 -> v1.9)
# If none match, .branch is written as an empty string.
set -euo pipefail
SCRIPT_NAME=get-versions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

OUTPUT_FILE="${1:-}"
[[ -n "$OUTPUT_FILE" ]] || die "usage: $(basename "$0") <output-yaml-file>"

KUBECONFIG_FILE=$(get_kubeconfig_file)
HARVESTER_BRANCH=""

detect_cluster_branch() {
  local kubeconfig="$1"
  local version os_image os_release variant_id

  log "Probing branch from Harvester server-version setting..."
  if version=$(get_harvester_setting "server-version" "$kubeconfig"); then
    if [[ "$version" =~ ^v?[0-9]+\.[0-9]+ ]]; then
      HARVESTER_BRANCH=$(sed -E 's/^v?([0-9]+)\.([0-9]+).*/v\1.\2/' <<<"$version")
      log "Detected branch $HARVESTER_BRANCH from server-version: $version"
      return 0
    fi
    log "server-version setting not usable (value: '${version:-<empty>}')"
  else
    log "Failed to query server-version setting; trying osImage"
  fi

  log "Probing branch from first node's osImage..."
  if os_image=$(get_first_node_os_image "$kubeconfig"); then
    if [[ "$os_image" =~ ^v?[0-9]+\.[0-9]+ ]]; then
      HARVESTER_BRANCH=$(sed -E 's/^v?([0-9]+)\.([0-9]+).*/v\1.\2/' <<<"$os_image")
      log "Detected branch $HARVESTER_BRANCH from osImage: $os_image"
      return 0
    fi
    log "osImage not usable (value: '${os_image:-<empty>}')"
  else
    log "Failed to query first node's osImage; trying VARIANT_ID"
  fi

  log "Probing branch from node1:/etc/os-release VARIANT_ID..."
  os_release=$(ssh_node "node1" "cat /etc/os-release" || true)
  # VARIANT_ID is assigned twice in Harvester's os-release (a generic
  # "transactional" value, then the Harvester-specific one) -- this is parsed
  # as plain text, not sourced, so take the last match explicitly.
  variant_id=$(awk -F= '/^VARIANT_ID=/{ value=substr($0, index($0, "=") + 1) } END { print value }' \
    <<<"$os_release" | tr -d '"')
  if [[ "$variant_id" =~ (v[0-9]+\.[0-9]+) ]]; then
    HARVESTER_BRANCH="${BASH_REMATCH[1]}"
    log "Detected branch $HARVESTER_BRANCH from VARIANT_ID: $variant_id"
    return 0
  fi

  log "VARIANT_ID not usable (value: '${variant_id:-<empty>}')"
  log "Could not detect Harvester branch; leaving empty"
}

detect_cluster_branch "$KUBECONFIG_FILE"

yq -n ".branch = \"$HARVESTER_BRANCH\"" > "$OUTPUT_FILE"
log "Wrote $OUTPUT_FILE"
