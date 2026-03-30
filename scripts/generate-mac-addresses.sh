#!/bin/bash -eu
# Generate random MAC addresses for node interfaces

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.yaml"

# Function to generate a random MAC address with 52:54:00 prefix (KVM/QEMU standard)
generate_mac() {
  printf "52:54:00:%02x:%02x:%02x" $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Config file not found at $CONFIG_FILE"
  exit 1
fi

# Get the number of nodes
NODE_COUNT=$(yq '.nodes | length' "$CONFIG_FILE")

echo "Generating MAC addresses for $NODE_COUNT nodes..."
echo ""

# Create a temporary file with the updated config
TMP_FILE=$(mktemp)
cp "$CONFIG_FILE" "$TMP_FILE"

# Generate MAC addresses for each node and interface
for ((node_idx=0; node_idx<NODE_COUNT; node_idx++)); do
  NODE_IP=$(yq ".nodes[$node_idx].ip" "$CONFIG_FILE")
  INTERFACE_COUNT=$(yq ".nodes[$node_idx].interfaces | length" "$CONFIG_FILE")
  
  echo "Node $((node_idx + 1)) (IP: $NODE_IP):"
  
  for ((iface_idx=0; iface_idx<INTERFACE_COUNT; iface_idx++)); do
    NEW_MAC=$(generate_mac)
    OLD_MAC=$(yq ".nodes[$node_idx].interfaces[$iface_idx].mac" "$CONFIG_FILE")
    BRIDGE=$(yq ".nodes[$node_idx].interfaces[$iface_idx].host_bridge" "$CONFIG_FILE")
    
    echo "  Interface $((iface_idx + 1)) ($BRIDGE): $OLD_MAC -> $NEW_MAC"
    
    # Use sed to update the MAC address in the temporary file
    # This preserves formatting better than yq -i
    sed -i "0,/$OLD_MAC/s/$OLD_MAC/$NEW_MAC/" "$TMP_FILE"
  done
  echo ""
done

# Move the temporary file back to the original
mv "$TMP_FILE" "$CONFIG_FILE"

echo "MAC addresses updated successfully in $CONFIG_FILE"
