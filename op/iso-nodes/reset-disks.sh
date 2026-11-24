#!/bin/bash -eu
# Replace the data disks of the ISO boot nodes (libvirt_volume.iso_node_data_disk).
# Only those volumes are targeted, so the rest of the infra, including the
# ISO copy in the pool (iso_boot.use_pool), is left untouched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
TF_DIR="${TOP_DIR}/terraform"

mapfile -t ADDRESSES < <(terraform -chdir="$TF_DIR" show -json |
    jq -r '.values.root_module.resources[]?.address | select(startswith("libvirt_volume.iso_node_data_disk"))'
    )

if [ "${#ADDRESSES[@]}" -eq 0 ]; then
    die "no ISO node data disks found in terraform state; run 'task admin-up' first"
fi

# Each address is a separate array element, so the ["..."] quotes in it
# reach terraform as is
ARGS=()
for addr in "${ADDRESSES[@]}"; do
    ARGS+=("-replace=$addr" "-target=$addr")
done

terraform -chdir="$TF_DIR" apply "${ARGS[@]}" --auto-approve
