#!/bin/bash -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="$SCRIPT_DIR/../config.yaml"
BASE_URL=$(yq -e '.harvester_release_url' "$CONFIG_FILE")

# Configuration
DOWNLOADS_DIR="$SCRIPT_DIR/isos"
DEST_DIR="/srv/www/htdocs/harvester"  # Change this variable as needed

# Get version from argument or use default
VERSION="${1:-master}"

# Function 1: Create downloads directory if needed
create_downloads_dir() {
    if [ ! -d "$DOWNLOADS_DIR" ]; then
        echo "Creating downloads directory..."
        mkdir -p "$DOWNLOADS_DIR"
    fi
}

# Function 2: Check and create version directory
check_version_dir() {
    local version_dir="$DOWNLOADS_DIR/harvester-$VERSION"

    # If version is master, always remove the directory to get fresh files
    if [ "$VERSION" = "master" ] && [ -d "$version_dir" ]; then
        echo "Version is master, removing existing directory to get fresh files..."
        rm -rf "$version_dir"
    fi

    if [ ! -d "$version_dir" ]; then
        echo "Creating directory for version $VERSION..."
        mkdir -p "$version_dir"
    fi
}

# Function 3: Download a single file if it doesn't exist
download_file() {
    local url="$1"
    local dest="$2"

    if [ ! -f "$dest" ]; then
        echo "Downloading $(basename "$dest") from $url..."
        curl -fL -o "$dest" "$url"
        if [ $? -ne 0 ]; then
            echo "Error downloading $url"
            return 1
        fi
    else
        echo "File $(basename "$dest") already exists, skipping..."
    fi
    return 0
}

# Function 4: Download all required files
download_all_files() {
    local version_dir="$DOWNLOADS_DIR/harvester-$VERSION"
    local base_url="$BASE_URL/$VERSION"

    download_file "${base_url}/harvester-${VERSION}-amd64.iso" \
        "${version_dir}/harvester-${VERSION}-amd64.iso"

    download_file "${base_url}/harvester-${VERSION}-amd64.sha512" \
        "${version_dir}/harvester-${VERSION}-amd64.sha512"

    download_file "${base_url}/harvester-${VERSION}-initrd-amd64" \
        "${version_dir}/harvester-${VERSION}-initrd-amd64"

    download_file "${base_url}/harvester-${VERSION}-vmlinuz-amd64" \
        "${version_dir}/harvester-${VERSION}-vmlinuz-amd64"

    download_file "${base_url}/harvester-${VERSION}-rootfs-amd64.squashfs" \
        "${version_dir}/harvester-${VERSION}-rootfs-amd64.squashfs"

    download_file "${base_url}/version.yaml" \
        "${version_dir}/version.yaml" || true
}

# Function 5: Validate checksum
validate_checksum() {
    local version_dir="$DOWNLOADS_DIR/harvester-$VERSION"
    local checked_file="checked"
    local filtered_sha512_file="harvester-${VERSION}-amd64.sha512.filtered"

    pushd "$version_dir" > /dev/null || return 1

    # Skip if already checked
    if [ -f "$checked_file" ]; then
        echo "Checksum already validated (checked file exists), skipping..."
	popd > /dev/null
        return 0
    fi

    echo "Validating checksum..."

    # Filter out net-install.iso line from checksum file
    grep -v "net-install.iso" "harvester-${VERSION}-amd64.sha512" > "$filtered_sha512_file"

    # Compare checksums
    if sha512sum -c "$filtered_sha512_file" 2>/dev/null; then
        echo "Checksum validation passed!"
        touch "$checked_file"
        rm -f "$filtered_sha512_file"  # Clean up filtered file
        popd > /dev/null
        return 0
    else
        echo "Checksum validation failed!"
        rm -f "$filtered_sha512_file"  # Clean up filtered file
        popd > /dev/null
        return 1
    fi
}

# Main execution
main() {
    echo "==========================================="
    echo "Preparing Harvester ISO for version: $VERSION"
    echo "==========================================="

    # Step 1: Create downloads directory
    create_downloads_dir

    # Step 2 & 3: Check/create version directory and download files
    check_version_dir
    download_all_files

    # Step 4: Validate checksum
    validate_checksum
    if [ $? -ne 0 ]; then
        echo "ERROR: Checksum validation failed. Exiting."
        exit 1
    fi

    echo "==========================================="
    echo "Done! All files prepared successfully."
    echo "==========================================="
}

# Run main function
main
