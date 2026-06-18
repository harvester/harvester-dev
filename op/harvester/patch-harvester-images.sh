#!/bin/bash -eu
# Patch the Harvester managed chart to use a custom image repository and tag.
# Usage: patch-harvester-images.sh <REPOSITORY> <TAG>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
KUBECONFIG="${KUBECONFIG:-${TOP_DIR}/kubeconfig}"

if [ $# -ne 2 ]; then
  echo "Usage: $(basename "$0") <REPOSITORY> <TAG>" >&2
  exit 1
fi

REPOSITORY="$1"
TAG="$2"

if [ ! -f "$KUBECONFIG" ]; then
  echo "Error: kubeconfig not found at $KUBECONFIG — run 'task op:nodes-get-kubeconfig' first" >&2
  exit 1
fi

export KUBECONFIG


patch_managed_chart() {
  echo "Patching harvester managed chart: repository=${REPOSITORY} tag=${TAG}"

  PATCH=$(cat <<EOF
spec:
  values:
    webhook:
      image:
        imagePullPolicy: Always
        repository: ${REPOSITORY}/harvester-webhook
        tag: ${TAG}
    containers:
      apiserver:
        image:
          imagePullPolicy: Always
          repository: ${REPOSITORY}/harvester
          tag: ${TAG}
EOF
)

  kubectl patch managedcharts.management.cattle.io harvester \
    -n fleet-local \
    --type=merge \
    --patch "$PATCH"

  echo "Patch applied successfully"
}

pause_managed_chart() {
  local chart=$1
  local do_pause=$2

  local PATCH
  PATCH=$(cat <<EOF
spec:
  paused: ${do_pause}
EOF
)

  kubectl patch managedcharts.management.cattle.io "$chart" \
    -n fleet-local \
    --type=merge \
    --patch "$PATCH"
}

wait_managed_chart() {
  namespace=$1
  name=$2
  version=$3
  generation=$4
  state=$5

  echo "Waiting for ManagedChart $namespace/$name from generation $generation"
  echo "Target version: $version, Target state: $state"

  local deadline=$(( $(date +%s) + 300 ))

  while [ true ]; do
    current_chart=$(kubectl get managedcharts.management.cattle.io $name -n $namespace -o yaml)
    current_version=$(echo "$current_chart" | yq e '.spec.version' -)
    current_observed_generation=$(echo "$current_chart" | yq e '.status.observedGeneration' -)
    current_state=$(echo "$current_chart" | yq e '.status.display.state' -)
    current_ready_clusters=$(echo "$current_chart" | yq e '.status.display.readyClusters' -)
    current_unavailable=$(echo "$current_chart" | yq e '.status.unavailable' -)
    echo "Current version: $current_version, Current ready clusters: $current_ready_clusters, Current state: $current_state, Current generation: $current_observed_generation, Current unavailable: $current_unavailable"

    if [ "$current_version" = "$version" ]; then
      if [ "$current_observed_generation" -gt "$generation" ]; then
        summary_state=$(echo "$current_chart" | yq e ".status.summary.$state" -)
        if [ "$summary_state" = "1" -a "$current_unavailable" = "0" ]; then
          break
        fi
      fi
    fi

    if (( $(date +%s) >= deadline )); then
      echo "Error: ManagedChart $namespace/$name did not reach state '$state' within 5 minutes" >&2
      return 1
    fi

    sleep 5
    echo "Sleep for 5 seconds to retry"
  done
}


pause_managed_chart harvester "true"
patch_managed_chart

# unpuased managed chart and wait it to be ready
chart_yaml=$(kubectl get managedcharts.management.cattle.io harvester -n fleet-local -o yaml)
current_version=$(echo "$chart_yaml" | yq e '.spec.version' -)
pre_generation=$(echo "$chart_yaml" | yq e '.status.observedGeneration' -)
pause_managed_chart harvester "false"
wait_managed_chart fleet-local harvester "$current_version" "$pre_generation" ready
