#!/bin/bash -e
# Install Rancher extensions

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

TOP_DIR=$(get_top_dir)
STATE_DIR=${TOP_DIR}/state

tf_init() {
    pushd $SCRIPT_DIR > /dev/null
    terraform -chdir=extensions init
}

install_rancher_extensions() {
    pushd $SCRIPT_DIR > /dev/null

    terraform -chdir=extensions apply --auto-approve
}

tf_init
install_rancher_extensions