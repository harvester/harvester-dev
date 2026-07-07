#!/bin/bash -eu

if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") ARTIFACT_SERVER_URL VERSION" >&2
    exit 1
fi

ARTIFACT_SERVER_URL="$1"
VERSION="$2"


TOP_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." &> /dev/null && pwd )"
source "$TOP_DIR/op/lib.sh"
source "$TOP_DIR/op/config.sh"
GOLDEN_DIR=$(golden_dir "$VERSION")
REMOTE_TIMESTAMP_URL="${ARTIFACT_SERVER_URL}/${VERSION}/latest"

is_valid() {
    local golden_dir="$1"

    if [[ ! -d "$golden_dir" ]]; then
        echo "Golden directory does not exist: ${golden_dir}" >&2
        return 1
    fi

    if [[ ! -f "${golden_dir}/timestamp" ]]; then
        echo "Timestamp file missing: ${golden_dir}/timestamp" >&2
        return 1
    fi

    local local_timestamp
    local_timestamp=$(cat "${golden_dir}/timestamp") || exit 1
    echo "Local timestamp: ${local_timestamp}" >&2

    local remote_timestamp
    echo "Fetching remote timestamp from ${REMOTE_TIMESTAMP_URL}..." >&2
    remote_timestamp=$(curl -fsSL "${REMOTE_TIMESTAMP_URL}") || exit 1
    echo "Remote timestamp: ${remote_timestamp}" >&2

    if [[ "$local_timestamp" != "$remote_timestamp" ]]; then
        echo "Timestamp mismatch: local=${local_timestamp} remote=${remote_timestamp}" >&2
        return 1
    fi

    return 0
}

golden_create() {
    cd "$TOP_DIR"

    echo "Creating golden image in ${GOLDEN_DIR}..." >&2

    local remote_timestamp
    remote_timestamp=$(curl -fsSL "${REMOTE_TIMESTAMP_URL}") || exit 1
    echo "Remote timestamp: ${remote_timestamp}" >&2

    local base="${ARTIFACT_SERVER_URL}/${VERSION}/${remote_timestamp}"
    yq e -i "
        .harvester_iso_url    = \"${base}/harvester-${VERSION}-amd64.iso\" |
        .harvester_kernel_url = \"${base}/harvester-${VERSION}-vmlinuz-amd64\" |
        .harvester_ramdisk_url = \"${base}/harvester-${VERSION}-initrd-amd64\" |
        .harvester_rootfs_url = \"${base}/harvester-${VERSION}-rootfs-amd64.squashfs\"
    " "${TOP_DIR}/config.yaml"
    echo "Updated config.yaml with remote base: ${base}"

    yq -i '.admin.egress_enabled = true' "${TOP_DIR}/config.yaml"

    task clean -- --force
    task up
    task op:nodes-golden-clean -- ${VERSION}
    task op:nodes-golden-create -- --timestamp "${remote_timestamp}" "${VERSION}"
}

if ! is_valid "$GOLDEN_DIR"; then
    golden_create
fi

task op:nodes-destroy
task op:nodes-golden-restore-and-boot -- ${VERSION}
