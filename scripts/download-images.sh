#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_DIR="$SCRIPT_DIR/../artifacts/images"

mkdir -p "$IMAGES_DIR"

download() {
    local url="$1"
    local dest="$2"

    if [[ -f "$dest" ]]; then
        echo "Skipping $(basename "$dest"), already exists."
        return
    fi

    echo "Downloading $(basename "$dest") from $url..."
    curl -fSL "$url" -o "$dest"
    echo "Done: $dest"
}

download_and_gunzip() {
    local url="$1"
    local dest="$2"

    if [[ -f "$dest" ]]; then
        echo "Skipping $(basename "$dest"), already exists."
        return
    fi

    echo "Downloading $(basename "$dest") from $url..."
    curl -fSL "$url" | gunzip > "$dest"
    echo "Done: $dest"
}

download_and_gunzip \
    "https://github.com/bk201/alpine-cloud-images/releases/download/20260520/3.23.4-x86_64-bios-cloudinit-vm-generic-20260520.img.gz" \
    "$IMAGES_DIR/alpine-admin.img"


download "https://cloud.debian.org/images/cloud/trixie/20260525-2489/debian-13-generic-amd64-20260525-2489.qcow2" "$IMAGES_DIR/debian-13-generic-amd64.qcow2"
download "http://cloud-images.ubuntu.com/noble/20260323/noble-server-cloudimg-amd64.img" "$IMAGES_DIR/noble-server-cloudimg-amd64.img"
download "https://download.opensuse.org/repositories/Cloud:/Images:/Leap_15.6/images/openSUSE-Leap-15.6.x86_64-NoCloud.qcow2" "$IMAGES_DIR/openSUSE-Leap-15.6.x86_64-NoCloud.qcow2"
