#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config.yaml"
IMAGES_DIR="$SCRIPT_DIR/../artifacts/images"

mkdir -p "$IMAGES_DIR"

download_image() {
    local name="$1"
    local url="$2"
    local dest="$IMAGES_DIR/$name"
    local lm_file="$IMAGES_DIR/${name}.last-modified"

    local headers server_lm
    if ! headers=$(curl -fsLI "$url"); then
        echo "Error: failed to fetch headers for $name ($url)" >&2
        return 1
    fi
    server_lm=$(echo "$headers" | grep -i "^last-modified:" | tr -d '\r' | sed 's/^[^:]*: //') || true

    if [[ -f "$dest" && -f "$lm_file" ]]; then
        local stored_lm
        stored_lm=$(cat "$lm_file")
        if [[ -n "$server_lm" && "$server_lm" == "$stored_lm" ]]; then
            echo "Skipping $name (up to date)."
            return
        fi
    fi

    echo "Downloading $name from $url..."
    local tmp
    tmp=$(mktemp "$IMAGES_DIR/${name}.tmp.XXXXXX")
    if [[ "$url" == *.gz ]]; then
        echo "Extracting $name (gunzip)..."
        curl -fSL "$url" | gunzip > "$tmp"
    else
        curl -fSL "$url" -o "$tmp"
    fi
    mv "$tmp" "$dest"
    chmod 644 "$dest"

    if [[ -n "$server_lm" ]]; then
        printf '%s' "$server_lm" > "$lm_file"
    fi
    echo "Done: $dest"
}

while IFS=$'\t' read -r name url; do
    echo "Processing image: $name"
    download_image "$name" "$url"
    echo ""
done < <(yq -r '.artifacts.images[] | [.name, .url] | @tsv' "$CONFIG")
