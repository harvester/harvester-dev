#!/bin/bash -eu
#
# set-node-egress.sh — enable or disable NAT masquerading on the admin node
#   so that Harvester nodes on the mgmt (eth1) and data (eth2) networks can
#   reach the outside world through eth0.
#
# Usage: set-node-egress.sh <1|0>
#   1 — enable egress (turns on ip_forward, installs iptables rules)
#   0 — disable egress (turns off ip_forward, removes iptables rules)
#
# The script SSHs into the admin node and:
#   1. Discovers eth1 and eth2 subnets dynamically via `ip route`.
#   2. Removes any existing MASQUERADE rules for those subnets (idempotent).
#   3. If enabling, adds:
#        eth1 subnet → eth0  (mgmt nodes to internet)
#        eth2 subnet → eth0  (data/storage nodes to internet)
#        eth2 subnet → eth1  (data/storage nodes to mgmt/Harvester VMs)

ENABLED="$1"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
SSH_CONFIG="$TOP_DIR/state/ssh_config"

remote_run() {
    ssh -F "$SSH_CONFIG" admin "$1"
}

remote_sudo() {
    local cmd="$1"
    ssh -F "$SSH_CONFIG" admin "sudo $cmd"
}

validate_subnet() {
    local subnet="$1" iface="$2"
    # bash-native CIDR check: x.x.x.x/prefix
    if [[ "$subnet" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        return 0
    fi
    echo "error: invalid subnet for $iface: '$subnet'" >&2
    exit 1
}

eth1_subnet=$(remote_run "ip route show dev eth1 scope link" | awk '{print $1}')
eth2_subnet=$(remote_run "ip route show dev eth2 scope link" | awk '{print $1}')
validate_subnet "$eth1_subnet" eth1
validate_subnet "$eth2_subnet" eth2

echo "eth1_subnet: $eth1_subnet"
echo "eth2_subnet: $eth2_subnet"

if [ "$ENABLED" = "1" ]; then
    echo "Enabling nodes egress..."
    remote_sudo "sysctl -w net.ipv4.ip_forward=1"
else
    echo "Disabling nodes egress..."
    remote_sudo "sysctl -w net.ipv4.ip_forward=0"
fi

remote_sudo "iptables -t nat -D POSTROUTING -o eth0 -s $eth1_subnet -j MASQUERADE 2>/dev/null || true"
remote_sudo "iptables -t nat -D POSTROUTING -o eth0 -s $eth2_subnet -j MASQUERADE 2>/dev/null || true"
remote_sudo "iptables -t nat -D POSTROUTING -o eth1 -s $eth2_subnet -j MASQUERADE 2>/dev/null || true"

if [ "$ENABLED" = "1" ]; then
    # traffic from eth1 and eth2 to the outside world via eth0
    remote_sudo "iptables -t nat -A POSTROUTING -o eth0 -s $eth1_subnet -j MASQUERADE"
    remote_sudo "iptables -t nat -A POSTROUTING -o eth0 -s $eth2_subnet -j MASQUERADE"

    # traffic from eth2 to harvester VM nodes via eth1
    remote_sudo "iptables -t nat -A POSTROUTING -o eth1 -s $eth2_subnet -j MASQUERADE"
fi

remote_sudo "iptables -t nat -L POSTROUTING"
