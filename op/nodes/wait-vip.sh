#!/bin/bash -e

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

CONFIG_FILE=$(get_config_file)
VIP=$(yq -e '.vip' "$CONFIG_FILE")

echo "Waiting for https://${VIP} to be reachable..."

timeout_minutes=20
max_attempts=$((timeout_minutes * 3))  # 3 attempts per minute (every 20 seconds)
count=0

while true; do
  if curl --insecure --silent --fail --max-time 5 "https://${VIP}" > /dev/null 2>&1; then
    echo "https://${VIP} is now reachable!"
    exit 0
  fi
  
  count=$((count + 1))
  if [ $count -ge $max_attempts ]; then
    echo "Error: Timeout reached after $timeout_minutes minutes. https://${VIP} is not reachable."
    exit 1
  fi
  
  echo "Not reachable yet... (checking again in 20 seconds)"
  sleep 20
done

