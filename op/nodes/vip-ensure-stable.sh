#!/bin/bash
# vip-ensure-stable.sh
# Probe the VIP; if unstable, find the current kube-vip lease holder, remove
# any stale `vip-*` macvlan devices left on the other nodes, then re-probe.
# See harvester-dev/docs/design/vip-workaround.md.
set -euo pipefail
SCRIPT_NAME=vip-ensure-stable
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"
source "$SCRIPT_DIR/../config.sh"

require_cmd ssh jq yq

ENSURE_VIP_STABLE=$(yq '.node_hacks.ensure_vip_stable // false' "$CONFIG_FILE")
if [[ "$ENSURE_VIP_STABLE" != "true" ]]; then
  log "node_hacks.ensure_vip_stable is not true, skipping"
  exit 0
fi

if "$SCRIPT_DIR/vip-probe.sh"; then
  log "VIP already stable, nothing to do"
  exit 0
fi

log "VIP probe failed, applying VIP workaround"

# step1: find the current lease holder
lease_yaml=$(ssh_node node1 "sudo -i kubectl get lease plndr-svcs-lock -n harvester-system -o yaml") \
  || die "failed to read plndr-svcs-lock lease from node1"
VIP_NODE=$(yq -e '.spec.holderIdentity' <<<"$lease_yaml") \
  || die "could not determine VIP_NODE (spec.holderIdentity) from lease"
log "current VIP holder: $VIP_NODE"

# step2: on every other node, remove stale vip-* macvlan devices
for i in $(seq 1 "${#NODES[@]}"); do
  host="node$i"
  if [[ "$host" == "$VIP_NODE" ]]; then
    log "$host: skipping (current VIP holder)"
    continue
  fi

  devices_json=$(ssh_node "$host" "ip -j link show type macvlan") || true
  if [[ -z "$devices_json" ]]; then
    log "$host: no macvlan devices"
    continue
  fi

  mapfile -t vip_ifaces < <(jq -r '.[] | select(.ifname | startswith("vip-")) | .ifname' <<<"$devices_json")
  if [[ ${#vip_ifaces[@]} -eq 0 ]]; then
    log "$host: no vip-* device found"
    continue
  fi

  for ifname in "${vip_ifaces[@]}"; do
    log "$host: removing stale device $ifname"
    ssh_node "$host" "sudo -i ip link del $ifname" || err "$host: failed to delete $ifname (continuing)"
  done
done

sleep 5

# step3: re-probe
log "re-probing VIP"
"$SCRIPT_DIR/vip-probe.sh" || die "VIP still unstable after workaround"
log "VIP is stable"
