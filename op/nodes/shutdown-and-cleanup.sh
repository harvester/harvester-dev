#!/usr/bin/env bash
# shutdown-cleanup.sh
# Tear down a test run by powering off the domains. The overlay disks are
# left in place: nodes:boot-from-golden deletes and recreates each overlay
# from its golden master before the next run, so deleting them here would be
# redundant -- and it would desync the on-disk volumes from Terraform state
# (terraform manages libvirt_volume.node_disk), breaking `task clean`.
# Golden masters and domain XML are always preserved.
# Overlay state is disposable, so we power off immediately (no graceful wait).
set -euo pipefail
SCRIPT_NAME=shutdown-cleanup
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
source "$SCRIPT_DIR/../config.sh"

require_cmd "$VIRSH"
# Instead of requiring root: confirm we can reach libvirt (all this script does
# is power off domains).
require_libvirt

# power off (immediate — overlay state is disposable and reset on next boot).
log "powering off domains"
for n in "${NODES[@]}"; do
  st=$(domain_state "$n" 2>/dev/null || true)
  if [[ "$st" == "running" || "$st" == "paused" ]]; then
    "$VIRSH" destroy "$n" >/dev/null 2>&1 || true
    log "  destroyed $n"
  else
    log "  $n already ${st:-undefined}"
  fi
done

log "shutdown complete. ready for next nodes:boot-from-golden."