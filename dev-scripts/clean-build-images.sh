#!/usr/bin/env bash
# Removes locally built Harvester Docker images and prunes dangling images.
#
# Targeted repos (matched by suffix):
#   */harvester, */harvester-webhook, */harvester-upgrade,
#   */harvester-os, */harvester-cluster-repo
#
# Tags skipped (treated as stable/pinned):
#   master, main, master-head, main-head, sle-micro-head
#
# Usage:
#   clean-build-images.sh        # lists candidates and prompts Y/N
#   clean-build-images.sh -f     # removes without prompting
#
# After removal, runs `docker image prune -f` to clean up dangling layers.
set -euo pipefail

trap 'docker image prune -f' EXIT

FORCE=false
if [[ "${1:-}" == "-f" ]]; then
  FORCE=true
fi

TARGET_SUFFIXES=(
  "/harvester"
  "/harvester-webhook"
  "/harvester-upgrade"
  "/harvester-os"
  "/harvester-cluster-repo"
)

SKIP_TAGS=(
  "master"
  "main"
  "master-head"
  "main-head"
  "sle-micro-head"
  "<none>"
)

is_skip_tag() {
  local tag="$1"
  for skip in "${SKIP_TAGS[@]}"; do
    if [[ "$tag" == "$skip" ]]; then
      return 0
    fi
  done
  return 1
}

mapfile -t ALL_IMAGES < <(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}')

TO_REMOVE=()

for entry in "${ALL_IMAGES[@]}"; do
  ref="${entry%% *}"
  id="${entry##* }"
  repo="${ref%:*}"
  tag="${ref##*:}"

  matched=false
  for suffix in "${TARGET_SUFFIXES[@]}"; do
    if [[ "$repo" == *"$suffix" ]]; then
      matched=true
      break
    fi
  done

  $matched || continue
  is_skip_tag "$tag" && continue

  TO_REMOVE+=("$ref")
done

if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
  echo "No matching images found."
  exit 0
fi


echo "Images to remove:"
for img in "${TO_REMOVE[@]}"; do
  echo "  $img"
done

if ! $FORCE; then
  echo ""
  read -r -p "Remove the above images? [Y/N] " answer
  if [[ "$answer" != "Y" && "$answer" != "y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

docker rmi "${TO_REMOVE[@]}"
