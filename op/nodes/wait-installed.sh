#!/bin/bash -e

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

CONFIG_FILE=$(get_config_file)

# Read prefix and node count from config.yaml using yq
PREFIX=$(yq '.provider.domain_prefix' "$CONFIG_FILE")
NODE_COUNT=$(yq '.node_count' "$CONFIG_FILE")

TIMEOUT_MINUTES=$(yq '.node_installed_timeout // 20' "$CONFIG_FILE")

echo "Waiting for all $NODE_COUNT node VMs to shut off..."

timeout_minutes=$TIMEOUT_MINUTES
max_attempts=$((timeout_minutes * 2))  # 2 attempts per minute (every 30 seconds)
count=0
start_time=$(date +%s)

while true; do
  echo "[$(date '+%Y-%m-%d %H:%M:%S')]"
  all_shutoff=true
  
  for i in $(seq 1 $((NODE_COUNT))); do
    domain_name="${PREFIX}-node${i}"
    state=$(virsh domstate "$domain_name" 2>/dev/null || echo "not found")
    
    if [ "$state" != "shut off" ]; then
      echo "Domain $domain_name is in state: $state"
      all_shutoff=false
    fi
  done
  
  if [ "$all_shutoff" = true ]; then
    elapsed=$(( $(date +%s) - start_time ))
    echo "All node VMs are shut off!"
    echo "Total time: ${elapsed}s"
    break
  fi
  
  count=$((count + 1))
  if [ $count -ge $max_attempts ]; then
    echo "Error: Timeout reached after $timeout_minutes minutes. Not all VMs shut off."
    exit 1
  fi
  
  echo "Waiting for VMs to shut off... (checking again in 30 seconds)"
  sleep 30
done
