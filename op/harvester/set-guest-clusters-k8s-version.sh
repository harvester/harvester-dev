#!/usr/bin/env bash
# Set .guest_clusters[].kubernetes_version in config.yaml to the newest
# version the configured Rancher version supports (from KDM).
# Usage: set-guest-clusters-k8s-version.sh [rke2|k3s]   (default: rke2)
set -euo pipefail
SCRIPT_NAME=set-guest-clusters-k8s-version
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

usage() {
  echo "usage: $(basename "$0") [rke2|k3s]" >&2
  exit 1
}

[[ $# -le 1 ]] || usage
DISTRO="${1:-rke2}"
case "$DISTRO" in
  rke2|k3s) ;;
  *) err "unknown distro: $DISTRO"; usage ;;
esac

require_cmd yq
CONFIG_FILE=${CONFIG_FILE:-$(get_config_file)}

count=$(yq '.guest_clusters | length' "$CONFIG_FILE")
[[ "$count" -gt 0 ]] || die "no .guest_clusters entries in $CONFIG_FILE"

VERSION=$("$SCRIPT_DIR/../rancher/list-kdm-versions.sh" --latest --distro "$DISTRO")
log "Latest $DISTRO version supported by Rancher: $VERSION"

yq -r '.guest_clusters[] | .name + " " + (.kubernetes_version // "<unset>")' "$CONFIG_FILE" |
  while read -r name old; do
    if [[ "$old" == "$VERSION" ]]; then
      log "$name: $old (unchanged)"
    else
      log "$name: $old -> $VERSION"
    fi
  done

VERSION="$VERSION" yq -i '.guest_clusters[].kubernetes_version = strenv(VERSION)' "$CONFIG_FILE"
log "Updated $CONFIG_FILE"
