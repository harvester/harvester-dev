#!/bin/bash -eu
#
# One-off migration of downloaded artifacts from the old layout
#   artifacts/isos/<prefix>-<version>/<prefix>-<version>-*
# to the release server layout
#   artifacts/isos/<prefix>/<version>/<prefix>-<version>-*
#
# File names don't change. Only directories that start with "<prefix>-"
# (harvester_release_prefix, or --prefix) and contain
# <dirname>-amd64.iso are moved. Run once per prefix you have downloads
# for. config.yaml isn't changed; run select-install-iso.sh and
# select-upgrade-iso.sh afterwards.
#
# Usage: migrate-isos-layout.sh [--prefix PREFIX] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/../config.yaml}"
ISOS_DIR="${ISOS_DIR:-$SCRIPT_DIR/isos}"

PREFIX=""
DRY_RUN=false

usage() {
  echo "Usage: $0 [--prefix PREFIX] [--dry-run]"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "Error: --prefix requires a value" >&2
        exit 1
      fi
      PREFIX="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "$PREFIX" ]; then
  PREFIX=$(yq -e '.harvester_release_prefix // "harvester"' "$CONFIG_FILE")
fi

moved=0
for dir in "$ISOS_DIR/$PREFIX"-*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  version="${name#"$PREFIX"-}"

  if [ ! -f "$dir/$name-amd64.iso" ]; then
    echo "skip:  $name (no $name-amd64.iso)"
    continue
  fi

  dest="$ISOS_DIR/$PREFIX/$version"
  if [ -e "$dest" ]; then
    echo "skip:  $name ($dest already exists)"
    continue
  fi

  echo "move:  $name -> $PREFIX/$version"
  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$ISOS_DIR/$PREFIX"
    mv "$dir" "$dest"
  fi
  moved=$((moved + 1))
done

if [ "$moved" -eq 0 ]; then
  echo "Nothing to migrate for prefix '$PREFIX' in $ISOS_DIR"
elif [ "$DRY_RUN" = true ]; then
  echo "Dry run: $moved directories would be moved"
else
  echo "Moved $moved directories. Re-run select-install-iso.sh and"
  echo "select-upgrade-iso.sh to update config.yaml."
fi
