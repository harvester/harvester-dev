#!/bin/bash -eu
# Delete guest clusters

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

pushd "$SCRIPT_DIR/guest-cluster" > /dev/null
terraform destroy
