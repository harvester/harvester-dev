#!/usr/bin/env bash
# golden-list.sh
# List all golden image versions of this repo_id with a summary from their
# metadata. Read-only; does not touch libvirt.
set -euo pipefail
SCRIPT_NAME=golden-list
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

require_cmd yq
CONFIG_FILE=${CONFIG_FILE:-$(get_config_file)}

base=$(golden_base_dir)
shopt -s nullglob
dirs=("$base"/*/)
if [[ ! -d "$base" || ${#dirs[@]} -eq 0 ]]; then
  echo "no golden images under $base"
  exit 0
fi

{
  printf 'VERSION\tNODES\tCREATED\tTIMESTAMP\tSIZE\n'
  for d in "${dirs[@]}"; do
    d=${d%/}
    version=$(basename "$d")
    meta=$(golden_meta_path "$version")
    nodes=- created=- ts=-
    if [[ -f "$meta" ]]; then
      nodes=$(yq '.node_count // "-"' "$meta")
      created=$(yq '.created_at // "-"' "$meta")
      ts=$(yq '.timestamp // "-"' "$meta")
    fi
    size=$(du -sh "$d" 2>/dev/null | cut -f1) || size=-
    printf '%s\t%s\t%s\t%s\t%s\n' "$version" "$nodes" "$created" "$ts" "${size:--}"
  done
} | column -t -s $'\t'
