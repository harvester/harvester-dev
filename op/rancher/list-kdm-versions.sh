#!/usr/bin/env bash
# List RKE2/K3s Kubernetes versions offered by a Rancher version, based on
# Kontainer Driver Metadata (KDM).
#
# Rancher fetches data.json from
#   https://releases.rancher.com/kontainer-driver-metadata/release-v2.<minor>/data.json
# and offers a release only if its own server version is within the release's
# [minChannelServerVersion, maxChannelServerVersion] range.
#
# Usage: list-kdm-versions.sh [--all|--latest] [--distro rke2|k3s] [--version vX.Y.Z]
#   --all       list every compatible patch (default: latest patch per minor,
#               like the Rancher UI)
#   --latest    print only the newest compatible version, nothing else
#               (requires --distro); meant for use by other scripts
#   --distro    only list one distro (default: rke2 and k3s)
#   --version   Rancher version (default: .rancher.version in config.yaml)
#
# Env:
#   KDM_URL     override the data.json URL (e.g. a dev-v2.x branch or mirror)
set -euo pipefail
SCRIPT_NAME=list-kdm-versions
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

usage() {
  echo "usage: $(basename "$0") [--all|--latest] [--distro rke2|k3s] [--version vX.Y.Z]" >&2
  exit 1
}

require_cmd curl jq yq

SHOW_ALL=false
LATEST_ONLY=false
DISTRO_SET=false
DISTROS=(rke2 k3s)
RANCHER_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all) SHOW_ALL=true; shift ;;
    --latest) LATEST_ONLY=true; shift ;;
    --distro)
      [[ $# -ge 2 ]] || usage
      case "$2" in
        rke2|k3s) DISTROS=("$2"); DISTRO_SET=true ;;
        *) err "unknown distro: $2"; usage ;;
      esac
      shift 2 ;;
    --version)
      [[ $# -ge 2 ]] || usage
      RANCHER_VERSION="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) err "unknown argument: $1"; usage ;;
  esac
done

if $LATEST_ONLY; then
  $DISTRO_SET || { err "--latest requires --distro"; usage; }
  $SHOW_ALL && { err "--latest and --all are mutually exclusive"; usage; }
fi

if [[ -z "$RANCHER_VERSION" ]]; then
  CONFIG_FILE=${CONFIG_FILE:-$(get_config_file)}
  RANCHER_VERSION=$(yq -e '.rancher.version' "$CONFIG_FILE") \
    || die "cannot read .rancher.version from $CONFIG_FILE"
fi

[[ "$RANCHER_VERSION" =~ ^v?([0-9]+)\.([0-9]+)\.[0-9]+ ]] \
  || die "invalid Rancher version: $RANCHER_VERSION"
[[ "$RANCHER_VERSION" == v* ]] || RANCHER_VERSION="v$RANCHER_VERSION"
BRANCH="release-v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
URL="${KDM_URL:-https://releases.rancher.com/kontainer-driver-metadata/${BRANCH}/data.json}"

DATA_FILE=$(mktemp)
trap 'rm -f "$DATA_FILE"' EXIT

log "Fetching KDM data from $URL" >&2
curl -fsSL "$URL" -o "$DATA_FILE" || die "failed to fetch $URL"

# Print compatible versions of distro $1, newest first.
compatible_versions() {
  jq -r --arg rv "$RANCHER_VERSION" --arg distro "$1" --argjson all "$SHOW_ALL" '
    # Semver sort key: [major, minor, patch, is_ga, prerelease].
    # A pre-release sorts below its GA (v2.14.0-alpha1 < v2.14.0).
    def semkey:
      ltrimstr("v") | split("+")[0] as $v
      | ($v | index("-")) as $i
      | (if $i then $v[:$i] else $v end) as $core
      | (if $i then $v[$i+1:] else "" end) as $pre
      | ($core | split(".") | map(tonumber)) + [(if $pre == "" then 1 else 0 end), $pre];
    ($rv | semkey) as $r
    | [ .[$distro].releases[]
        | select((.minChannelServerVersion | semkey) <= $r
                 and $r <= (.maxChannelServerVersion | semkey)) ]
    # Tie-break on the build revision (+rke2r3 > +rke2r1).
    | sort_by((.version | semkey),
              (.version | (capture("\\+[a-z0-9]*?r?(?<n>[0-9]+)$").n // "0") | tonumber))
    | if $all then . else
        group_by(.version | semkey | .[0:2]) | map(last)
      end
    | reverse
    | .[].version
  ' "$DATA_FILE"
}

if $LATEST_ONLY; then
  latest=$(compatible_versions "${DISTROS[0]}" | head -n1)
  [[ -n "$latest" ]] || die "no ${DISTROS[0]} version compatible with Rancher $RANCHER_VERSION"
  echo "$latest"
  exit 0
fi

echo "Rancher $RANCHER_VERSION (KDM: $URL)"
for distro in "${DISTROS[@]}"; do
  echo "${distro}:"
  versions=$(compatible_versions "$distro")
  if [[ -z "$versions" ]]; then
    echo "  (none)"
  else
    sed 's/^/  /' <<<"$versions"
  fi
done

echo
echo "Note: KDM is fetched at runtime, so new patch releases can appear without upgrading Rancher."
