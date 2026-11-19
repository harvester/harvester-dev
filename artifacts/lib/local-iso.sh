# Shared helpers for select-install-iso.sh and select-upgrade-iso.sh.
# Source this file; don't run it.
#
# Local artifacts mirror the release server layout:
#   artifacts/isos/<prefix>/<version>/<prefix>-<version>-*
# so <artifact_server_url>/isos/<prefix> serves like harvester_release_url.
#
# The caller sets CONFIG_FILE and ISOS_DIR, then calls:
#   local_iso_select [VERSION]   # sets VERSION, NAME, BASE_URL, ...
#   local_url FILE               # artifact server URL for a release file

# Pick VERSION from the argument or an interactive menu of the versions
# downloaded for harvester_release_prefix. Sets RELEASE_PREFIX, VERSION,
# NAME and BASE_URL.
local_iso_select() {
  local artifact_server_url prefix_dir dir v index selection valid
  local -a versions=()

  artifact_server_url=$(yq -e '.artifact_server_url' "$CONFIG_FILE")
  artifact_server_url="${artifact_server_url%/}"
  RELEASE_PREFIX=$(yq -e '.harvester_release_prefix // "harvester"' "$CONFIG_FILE")
  prefix_dir="$ISOS_DIR/$RELEASE_PREFIX"

  for dir in "$prefix_dir"/*/; do
    [ -d "$dir" ] && versions+=("$(basename "$dir")")
  done

  if [ ${#versions[@]} -eq 0 ]; then
    echo "Error: no $RELEASE_PREFIX versions found in $prefix_dir" >&2
    echo "       (run ./artifacts/download-harvester-iso.sh VERSION first)" >&2
    exit 1
  fi

  if [ $# -ge 1 ]; then
    VERSION="$1"
    valid=false
    for v in "${versions[@]}"; do
      if [ "$v" = "$VERSION" ]; then
        valid=true
        break
      fi
    done
    if [ "$valid" != true ]; then
      echo "Error: '$VERSION' is not a valid version. Available versions:" >&2
      printf '  %s\n' "${versions[@]}" >&2
      exit 1
    fi
  else
    echo "Available $RELEASE_PREFIX versions:"
    echo ""
    index=1
    for v in "${versions[@]}"; do
      echo "  $index) $v"
      index=$((index + 1))
    done
    echo ""

    read -r -p "Select version [1-${#versions[@]}] (default: 1): " selection
    selection=${selection:-1}

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#versions[@]}" ]; then
      echo "Error: Invalid selection. Please choose a number between 1 and ${#versions[@]}" >&2
      exit 1
    fi
    VERSION="${versions[$((selection - 1))]}"
  fi

  NAME="${RELEASE_PREFIX}-${VERSION}"
  BASE_URL="$artifact_server_url/isos/$RELEASE_PREFIX/$VERSION"

  echo "Selected version: $VERSION"
  if [ ! -f "$prefix_dir/$VERSION/checked" ]; then
    echo "Warning: $prefix_dir/$VERSION has no 'checked' file; checksums weren't verified" >&2
  fi
}

# Print the artifact server URL for a file in the selected version, after
# checking that the file exists locally.
# Usage: local_url FILE
local_url() {
  local path="$ISOS_DIR/$RELEASE_PREFIX/$VERSION/$1"
  if [ ! -f "$path" ]; then
    echo "Error: missing $path; config.yaml not changed" >&2
    exit 1
  fi
  echo "$BASE_URL/$1"
}
