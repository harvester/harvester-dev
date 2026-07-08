#!/bin/bash -eu
#
# Downloads Harvester artifacts for a given VERSION into a
# timestamped subdirectory under DOWNLOAD_BASE_DIR/VERSION/.
#
# The remote Last-Modified time of the sha512 checksum file is used as the
# version identifier (REMOTE_TIMESTAMP). If a matching directory already
# contains a "checked" sentinel file, the download is skipped and "latest" is
# updated in place. Otherwise, artifacts are downloaded fresh, verified with
# sha512sum (excluding net-install.iso), and "checked" is touched on success.
# The "latest" file is always updated to REMOTE_TIMESTAMP on a successful run.
# Old timestamped directories beyond MAX_RETAINS are pruned.
#
# Usage: download-golden-iso.sh [--max-retains N] VERSION DOWNLOAD_BASE_DIR
#
# Directory structure:
#   DOWNLOAD_BASE_DIR/
#   └── VERSION/
#       ├── latest                          <- contains REMOTE_TIMESTAMP string
#       ├── 20240601T120000Z/               <- older, may be pruned
#       │   ├── harvester-VERSION-amd64.sha512
#       │   ├── harvester-VERSION-initrd-amd64
#       │   ├── harvester-VERSION-vmlinuz-amd64
#       │   ├── harvester-VERSION-rootfs-amd64.squashfs
#       │   ├── version.yaml
#       │   └── checked
#       └── 20240702T083000Z/               <- newest, always kept
#           └── ...

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.yaml"

MAX_RETAINS=2

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-retains)
            MAX_RETAINS="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -lt 2 ]]; then
    echo "Usage: $(basename "$0") [--max-retains N] VERSION DOWNLOAD_BASE_DIR" >&2
    exit 1
fi

VERSION="$1"
DOWNLOAD_BASE_DIR="$2"

BASE_URL=$(yq -e '.harvester_release_url' "$CONFIG_FILE")
VERSION_DIR="${DOWNLOAD_BASE_DIR}/${VERSION}"

download_file() {
    local url="$1"
    local dest="$2"

    echo "Downloading $url to $dest..." >&2
    curl -fL -o "$dest" "$url"
}

mkdir -p "$VERSION_DIR"

REMOTE_CHECKSUM_URL="${BASE_URL}/${VERSION}/harvester-${VERSION}-amd64.sha512"
last_modified=$(curl -fsSI "$REMOTE_CHECKSUM_URL" \
    | grep -i "^last-modified:" | cut -d' ' -f2- | tr -d '\r')
REMOTE_TIMESTAMP=$(date -d "$last_modified" "+%Y%m%dT%H%M%SZ")
echo "Remote timestamp of $REMOTE_CHECKSUM_URL: ${REMOTE_TIMESTAMP}" >&2

if [[ -f "${VERSION_DIR}/${REMOTE_TIMESTAMP}/checked" ]]; then
    echo "Already up to date: ${REMOTE_TIMESTAMP}" >&2
    echo "$REMOTE_TIMESTAMP" > "${VERSION_DIR}/latest"
    echo "Update latest timestamp to ${REMOTE_TIMESTAMP}."
    exit 0
fi


ts_dir="${VERSION_DIR}/${REMOTE_TIMESTAMP}"
mkdir -p "$ts_dir"

base_url="${BASE_URL}/${VERSION}"

download_file "${base_url}/harvester-${VERSION}-amd64.iso" \
    "${ts_dir}/harvester-${VERSION}-amd64.iso"

download_file "${base_url}/harvester-${VERSION}-amd64.sha512" \
    "${ts_dir}/harvester-${VERSION}-amd64.sha512"

download_file "${base_url}/harvester-${VERSION}-initrd-amd64" \
    "${ts_dir}/harvester-${VERSION}-initrd-amd64"

download_file "${base_url}/harvester-${VERSION}-vmlinuz-amd64" \
    "${ts_dir}/harvester-${VERSION}-vmlinuz-amd64"

download_file "${base_url}/harvester-${VERSION}-rootfs-amd64.squashfs" \
    "${ts_dir}/harvester-${VERSION}-rootfs-amd64.squashfs"


echo "Validating checksum..." >&2
filtered_sha512="${ts_dir}/harvester-${VERSION}-amd64.sha512.filtered"
grep -v "net-install.iso" "${ts_dir}/harvester-${VERSION}-amd64.sha512" > "$filtered_sha512"
pushd "$ts_dir" > /dev/null
if sha512sum -c "$filtered_sha512" 2>/dev/null; then
    echo "Checksum validation passed." >&2
    rm -f "$filtered_sha512"
    touch "${ts_dir}/checked"
else
    rm -f "$filtered_sha512"
    echo "Checksum validation failed." >&2
    popd > /dev/null
    exit 1
fi
popd > /dev/null

echo "$REMOTE_TIMESTAMP" > "${VERSION_DIR}/latest"
echo "Update latest timestamp to ${REMOTE_TIMESTAMP}"

mapfile -t dirs < <(find "$VERSION_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
count=${#dirs[@]}
if [[ $count -gt $MAX_RETAINS ]]; then
    for (( i=0; i < count - MAX_RETAINS; i++ )); do
        echo "Removing old: ${dirs[$i]}" >&2
        rm -rf "${dirs[$i]}"
    done
fi
