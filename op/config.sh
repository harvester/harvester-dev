#!/usr/bin/env bash
# config.sh — shared configuration. Source-only; do NOT execute directly.
#
# Design invariants:
#   * golden images are READ-ONLY masters and are never modified after creation
#   * domain XML is NEVER touched — overlays are recreated at the *same* disk
#     paths the XML already references
#   * per-test reset = delete overlay + recreate overlay from golden (instant)

# --- topology (derived from config.yaml) ------------------------------------

# config.yaml is the single source of truth. Domain names follow the same
# convention as op/nodes/libvirt-domain-op.sh ("${domain_prefix}-node${i}"),
# and NODE_IPS are read from the per-node `.nodes[].ip` entries, index-aligned
# with NODES. Both honor `.node_count` (the number of *enabled* nodes).
#
# Override by exporting NODES *and* NODE_IPS before sourcing, e.g.:
#   NODES=(hvst-node1) NODE_IPS=(10.8.0.11) ./nodes/create-golden.sh
CONFIG_FILE=${CONFIG_FILE:-$(get_config_file)}

if [[ -z "${NODES+x}" || -z "${NODE_IPS+x}" ]]; then
  _prefix=$(yq -e '.provider.domain_prefix' "$CONFIG_FILE")
  _count=$(yq -e '.node_count' "$CONFIG_FILE")

  NODES=()
  NODE_IPS=()
  for _i in $(seq 1 "$_count"); do
    NODES+=("${_prefix}-node${_i}")
    NODE_IPS+=("$(yq -e ".nodes[$((_i - 1))].ip" "$CONFIG_FILE")")
  done
  unset _prefix _count _i
fi

# --- paths / tools ----------------------------------------------------------

# Read-only golden masters live here. Kept under the default libvirt image dir
# so qemu/AppArmor can read them as backing files without extra profile rules.
GOLDEN_DIR=${GOLDEN_DIR:-/var/lib/libvirt/images/golden}

VIRSH=${VIRSH:-virsh}
QEMU_IMG=${QEMU_IMG:-qemu-img}

# Ownership/permissions applied to freshly created overlay disks so the
# libvirt-qemu process can open them read-write.
OVERLAY_OWNER=${OVERLAY_OWNER:-libvirt-qemu:kvm}

# --- golden creation: coordinated shutdown ---------------------------------

# Seconds to wait for a graceful, coordinated shutdown before giving up.
SHUTDOWN_TIMEOUT=${SHUTDOWN_TIMEOUT:-180}

# If graceful shutdown times out at golden-creation time: 0 = abort (safe,
# default), 1 = force `virsh destroy`. Forcing risks an etcd-inconsistent
# golden, so only enable if you understand the trade-off.
FORCE_DESTROY_ON_TIMEOUT=${FORCE_DESTROY_ON_TIMEOUT:-0}

# --- boot: readiness wait ---------------------------------------------------

READY_TIMEOUT=${READY_TIMEOUT:-600}        # overall wait budget (s)
READY_POLL_INTERVAL=${READY_POLL_INTERVAL:-10}
# Readiness now waits until ALL nodes report Ready (total is taken from kubectl
# itself, via the first control-plane node), so no fixed node count is needed.

# The readiness probe SSHes to nodes via the Terraform-generated
# state/ssh_config (host aliases node1..nodeN), so no key/user is configured
# here -- see ssh_node() in lib.sh.

# Remote command run on the first reachable node; should print `kubectl get
# nodes --no-headers` style output. Ready-count is computed locally from this.
# >>> this is the readiness hook you said you'd fill in / adjust <<<
REMOTE_GET_NODES_CMD=${REMOTE_GET_NODES_CMD:-'sudo -i kubectl get nodes --no-headers'}