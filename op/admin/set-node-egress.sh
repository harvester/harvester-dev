#!/bin/bash -eu

ENABLED="$1"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
SSH_CONFIG="$TOP_DIR/state/ssh_config"

remote_sudo() {
    local cmd="$1"
    ssh -F "$SSH_CONFIG" admin "sudo $cmd"
}

iptables_cmd=""

if [ "$ENABLED" = "1" ]; then
    iptables_cmd="-A"
    echo "Enabling nodes egress..."
    remote_sudo "sysctl -w net.ipv4.ip_forward=1"
else
    iptables_cmd="-D"
    echo "Disabling nodes egress..."
fi

remote_sudo "iptables -t nat $iptables_cmd POSTROUTING -o eth0 -s 10.8.0.0/24 -j MASQUERADE"
remote_sudo "iptables -t nat $iptables_cmd POSTROUTING -o eth0 -s 10.9.0.0/24 -j MASQUERADE"
remote_sudo "iptables -t nat $iptables_cmd POSTROUTING -o eth1 -s 10.9.0.0/24 -j MASQUERADE"
remote_sudo "iptables -t nat -L POSTROUTING"
