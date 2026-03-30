#!/bin/bash -x
# replace all libvirt_volume.node_disk resources

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
TF_DIR="${TOP_DIR}/terraform"

mapfile -t ADDRESSES < <(terraform -chdir="$TF_DIR" show -json |
    jq -r '.values.root_module.resources[].address | select(startswith("libvirt_volume.node_disk"))'
    )

# Using an array (rather than a string) avoids shell quoting issues — each element is passed as a separate argument, so the ["0"] inner quotes are never interpreted by the shell.
# -replace=libvirt_volume.node_disk["0"]
# -replace=libvirt_volume.node_disk["1"]
# -replace=libvirt_volume.node_disk["2"]
REPLACE_ARGS=()
for addr in "${ADDRESSES[@]}"; do
    REPLACE_ARGS+=("-replace=$addr")
done

terraform -chdir="$TF_DIR" apply "${REPLACE_ARGS[@]}" --auto-approve
