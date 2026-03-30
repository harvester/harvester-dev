#!/bin/bash -eu
# Change the default dashboard admin password

# Get the script directory and config file location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

CONFIG_FILE=$(get_config_file)

# Read configuration from config.yaml
HARVESTER_VIP=$(yq -e '.vip' "$CONFIG_FILE")
NEW_PASSWORD=$(yq -e '.harvester.admin_password' "$CONFIG_FILE")

HARVESTER_ENDPOINT="https://${HARVESTER_VIP}"
DEFAULT_PASSWORD="admin"
DEFAULT_USERNAME="admin"

echo "Harvester endpoint: $HARVESTER_ENDPOINT"

# Function to login and get token
get_auth_token() {
  local username="$1"
  local password="$2"
  
  local response
  response=$(curl -sk -X POST \
    "${HARVESTER_ENDPOINT}/v3-public/localProviders/local?action=login" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"username\":\"${username}\",\"password\":\"${password}\"}")
  
  local token
  token=$(echo "$response" | jq -r '.token // empty')
  
  if [ -z "$token" ]; then
    echo "Error: Failed to get authentication token" >&2
    echo "Response: $response" >&2
    return 1
  fi
  
  echo "$token"
}

# Function to change password
change_password() {
  local token="$1"
  local current_password="$2"
  local new_password="$3"
  
  echo "Changing admin password..."
  
  local status_code
  status_code=$(curl -sk -X POST \
    "${HARVESTER_ENDPOINT}/v3/users?action=changepassword" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${token}" \
    -d "{\"currentPassword\":\"${current_password}\",\"newPassword\":\"${new_password}\"}" \
    -w "%{http_code}" \
    -o /dev/null)
  
  if [ "$status_code" -eq 200 ]; then
    echo "Password changed successfully!"
    return 0
  else
    echo "Failed to change password. HTTP status code: $status_code"
    return 1
  fi
}

# Main execution
echo "Starting password change process..."

# Get authentication token
TOKEN=$(get_auth_token "$DEFAULT_USERNAME" "$DEFAULT_PASSWORD")

if [ -z "$TOKEN" ]; then
  echo "Error: Failed to get authentication token"
  exit 1
fi

# Change password
if change_password "$TOKEN" "$DEFAULT_PASSWORD" "$NEW_PASSWORD"; then
  echo "Password change completed successfully!"
  exit 0
else
  echo "Error: Failed to change password"
  exit 1
fi

