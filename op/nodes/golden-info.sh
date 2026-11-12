#!/usr/bin/env bash
# golden-info.sh
# Show the metadata and disk files of a golden image version. Read-only; does
# not touch libvirt.
set -euo pipefail
SCRIPT_NAME=golden-info
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

GOLDEN_VERSION="${1:-}"
[[ -n "$GOLDEN_VERSION" ]] || die "usage: $(basename "$0") <version>  (e.g. v1.8)"

require_cmd yq
CONFIG_FILE=${CONFIG_FILE:-$(get_config_file)}

dir=$(golden_dir "$GOLDEN_VERSION")
[[ -d "$dir" ]] || die "golden image not found: $dir"
meta=$(golden_meta_path "$GOLDEN_VERSION")

echo "Path: $dir"
echo
echo "Metadata ($meta):"
if [[ -f "$meta" ]]; then
  yq '.' "$meta" | sed 's/^/  /'
else
  echo "  (missing)"
fi
echo
echo "Disks:"
shopt -s nullglob
disks=("$dir"/*.qcow2)
if [[ ${#disks[@]} -eq 0 ]]; then
  echo "  (none)"
else
  for f in "${disks[@]}"; do
    printf '  %-8s %s\n' "$(du -h "$f" | cut -f1)" "$(basename "$f")"
  done
fi
