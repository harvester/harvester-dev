#!/usr/bin/env bash
# clean-golden.sh
# Remove the golden master directory. Best-effort: missing dir is not an error.
# Golden masters are created as root (read-only), so fall back to sudo if a
# plain rm is denied.
set -euo pipefail
SCRIPT_NAME=clean-golden
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
source "$SCRIPT_DIR/../config.sh"

# Optional version: clean only $GOLDEN_DIR/<version>; omit to clean everything.
GOLDEN_VERSION="${1:-}"
target="$(golden_dir)"

if [[ ! -d "$target" ]]; then
  log "no golden dir at $target (nothing to clean)"
  exit 0
fi

if rm -rf "$target" 2>/dev/null; then
  log "removed golden dir $target"
elif sudo rm -rf "$target"; then
  log "removed golden dir $target (via sudo)"
else
  err "failed to remove golden dir $target (continuing anyway)"
fi
