#!/usr/bin/env bash
# boot-from-golden.sh
# Recreate fresh overlays on top of the read-only golden masters (at the same
# disk paths the domain XML already references), start the cluster, and wait
# until it is ready. Exits 0 when ready, 1 on timeout — suitable for CI gating.
set -euo pipefail
SCRIPT_NAME=boot-from-golden
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
source "$SCRIPT_DIR/../config.sh"

# Version tag to boot from; overlays back onto $GOLDEN_DIR/<version> masters.
GOLDEN_VERSION="${1:-}"
[[ -n "$GOLDEN_VERSION" ]] || die "usage: $(basename "$0") <version>  (e.g. v1.8)"

require_cmd "$VIRSH" "$QEMU_IMG" ssh curl yq
# Instead of requiring root: confirm we can reach libvirt now, and (per disk, in
# step 1) that the golden is readable and the overlay's dir is writable.
require_libvirt

for n in "${NODES[@]}"; do
  domain_exists "$n" || die "domain not found: $n"
done

# 0) gate: every node must be shut off BEFORE we touch any overlay. A still-
#    running VM almost always means a previous test run is still in progress,
#    so we abort the whole thing and clobber nothing.
for n in "${NODES[@]}"; do
  st=$(domain_state "$n" || true)
  if [[ "$st" != "shut off" && -n "$st" ]]; then
    die "$n is '$st' — a previous run may still be in progress.
     Refusing to boot so a live test environment is not clobbered.
     Run nodes:shutdown-and-cleanup first, then retry."
  fi
done

# 1) fresh overlay per disk, backing = golden. XML is never modified.
log "step:  recreating overlays from golden"
for n in "${NODES[@]}"; do
  while read -r target src; do
    [[ -n "$target" ]] || continue
    g=$(golden_path "$n" "$target")
    [[ -f "$g" ]] || die "golden missing for $n/$target: $g (run nodes:create-golden first)"
    require_readable "$g"
    require_writable_dir "$src"
    log "  $n ($target): overlay $src  (backing $g)"
    rm -f "$src"
    "$QEMU_IMG" create -f qcow2 -b "$g" -F qcow2 "$src" >/dev/null
    chown "$OVERLAY_OWNER" "$src" 2>/dev/null || true
    chmod 0660 "$src" 2>/dev/null || true
  done < <(domain_disks "$n")
done

