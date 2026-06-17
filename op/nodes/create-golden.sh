#!/usr/bin/env bash
# create-golden.sh
# Capture the current cluster state as read-only golden masters.
# Run this once whenever you want to freeze a freshly-built cluster
# (e.g. once per day in the build phase). Whatever state the cluster is
# in *now* is what gets frozen.
set -euo pipefail
SCRIPT_NAME=create-golden
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
source "$SCRIPT_DIR/../config.sh"

# Version tag for this golden set; masters are written under $GOLDEN_DIR/<version>.
GOLDEN_VERSION="${1:-}"
[[ -n "$GOLDEN_VERSION" ]] || die "usage: $(basename "$0") <version>  (e.g. v1.8)"

require_cmd "$VIRSH" "$QEMU_IMG"
# Instead of requiring root: confirm we can reach libvirt now, and (per disk, in
# step 2) that the source disk is readable and the golden dir is writable.
require_libvirt

for n in "${NODES[@]}"; do
  domain_exists "$n" || die "domain not found: $n"
done

mkdir -p "$(golden_dir)"

# 1) etcd consistency: all three nodes must be cleanly shut down *together*
#    before we read their disks, so the captured etcd revisions are aligned.
log "step 1/2: coordinated shutdown (etcd-consistent capture)"
coordinated_shutdown \
  || die "nodes did not all shut down within ${SHUTDOWN_TIMEOUT}s \
(set FORCE_DESTROY_ON_TIMEOUT=1 to override, at the cost of etcd consistency)"

# 2) copy each disk into a standalone, read-only golden master.
#    This relies on the invariant that create-golden runs exactly ONCE, on a
#    freshly-installed cluster, so each source is a self-contained qcow2 with no
#    backing chain. We copy (cp --reflink=auto: instant CoW clone on btrfs/xfs,
#    plain copy otherwise) instead of `qemu-img convert` to stay fast. A copy of
#    an overlay would only capture the delta, so we hard-refuse any source that
#    has a backing file rather than silently producing a broken golden.
log "step 2/2: copying disks -> read-only golden masters"
for n in "${NODES[@]}"; do
  log "working with node $n"
  while read -r target src; do
    [[ -n "$target" ]] || continue
    g=$(golden_path "$n" "$target")
    [[ -f "$src" ]] || die "source disk missing: $src"
    require_readable "$src"
    require_writable_dir "$g"
    if "$QEMU_IMG" info "$src" | grep -q '^backing file:'; then
      die "$src has a backing chain -- create-golden must run once on a fresh \
cluster, not after boot-from-golden (refusing to copy an overlay)"
    fi
    log "  $n ($target): $src -> $g"
    rm -f "$g"
    cp --reflink=auto --sparse=always "$src" "$g"
    chmod 0444 "$g"
    "$QEMU_IMG" info "$g" | sed 's/^/      /'
  done < <(domain_disks "$n")
done

log "golden masters (version $GOLDEN_VERSION) written to $(golden_dir) (read-only)."
log "source cluster left shut off. done."