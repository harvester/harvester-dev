#!/bin/bash -e

usage() {
    echo "Usage: $0 --nat NAME,SUBNET --mgmt NAME,SUBNET --data NAME,SUBNET CONFIG"
    echo "Example: $0 --nat hvst-libvirt,192.168.123.0/24 --mgmt hvst-mgmt,10.5.0.0/24 --data hvst-data,10.6.0.0/24 config.yaml"
    echo "All subnets must be in X.X.X.0/24 form."
    exit 1
}

validate_subnet() {
    local subnet="$1"
    if [[ ! "$subnet" =~ ^([0-9]{1,3}\.){3}0/24$ ]]; then
        echo "Error: '$subnet' is not a valid X.X.X.0/24 subnet" >&2
        usage
    fi
}

parse_name_subnet() {
    local arg="$1" flag="$2"
    if [[ "$arg" != *,* ]]; then
        echo "Error: $flag value must be in NAME,SUBNET form (got '$arg')" >&2
        usage
    fi
    echo "${arg%%,*}" "${arg#*,}"
}

NAT_ARG="" MGMT_ARG="" DATA_ARG="" SKIP_ARTIFACTS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --nat)             NAT_ARG="$2";      shift 2 ;;
        --mgmt)            MGMT_ARG="$2";     shift 2 ;;
        --data)            DATA_ARG="$2";     shift 2 ;;
        --skip-artifacts)  SKIP_ARTIFACTS=true; shift ;;
        -*)     echo "Error: unknown option '$1'" >&2; usage ;;
        *)      break ;;
    esac
done

CONFIG="${1:-}"

if [[ -z "$NAT_ARG" || -z "$MGMT_ARG" || -z "$DATA_ARG" ]]; then
    echo "Error: --nat, --mgmt, and --data are all required" >&2
    usage
fi

if [[ -z "$CONFIG" ]]; then
    echo "Error: config file path is required" >&2
    usage
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "Error: config file not found: $CONFIG" >&2
    exit 1
fi

read -r NEW_NAT_NAME  NAT_SUBNET  <<< "$(parse_name_subnet "$NAT_ARG"  "--nat")"
read -r NEW_MGMT_NAME MGMT_SUBNET <<< "$(parse_name_subnet "$MGMT_ARG" "--mgmt")"
read -r NEW_DATA_NAME DATA_SUBNET <<< "$(parse_name_subnet "$DATA_ARG" "--data")"

validate_subnet "$NAT_SUBNET"
validate_subnet "$MGMT_SUBNET"
validate_subnet "$DATA_SUBNET"

NEW_NAT_BASE="${NAT_SUBNET%.0/24}"
NEW_MGMT_BASE="${MGMT_SUBNET%.0/24}"
NEW_DATA_BASE="${DATA_SUBNET%.0/24}"

# Update network names and all directly-computable address fields
yq -i "
  .networks.nat.bridge_name  = \"${NEW_NAT_NAME}\"        |
  .networks.nat.bridge_ip    = \"${NEW_NAT_BASE}.1\"      |
  .networks.nat.dhcp_start   = \"${NEW_NAT_BASE}.5\"      |
  .networks.nat.dhcp_end     = \"${NEW_NAT_BASE}.15\"     |
  .networks.mgmt.bridge_name = \"${NEW_MGMT_NAME}\"       |
  .networks.mgmt.bridge_ip   = \"${NEW_MGMT_BASE}.1\"     |
  .networks.mgmt.dhcp_start  = \"${NEW_MGMT_BASE}.50\"    |
  .networks.mgmt.dhcp_end    = \"${NEW_MGMT_BASE}.60\"    |
  .networks.data.bridge_name = \"${NEW_DATA_NAME}\"       |
  .networks.data.bridge_ip   = \"${NEW_DATA_BASE}.1\"     |
  .networks.data.dhcp_start  = \"${NEW_DATA_BASE}.100\"   |
  .networks.data.dhcp_end    = \"${NEW_DATA_BASE}.200\"   |
  .vip                       = \"${NEW_MGMT_BASE}.100\"   |
  .admin.interfaces           = [{\"ip\": \"${NEW_MGMT_BASE}.10/24\"}, {\"ip\": \"${NEW_DATA_BASE}.10/24\"}] |
  .rancher.interfaces         = [{\"ip\": \"${NEW_MGMT_BASE}.5/24\"}] |
  .rancher.hostname           = \"rancher.${NEW_MGMT_BASE}.5.sslip.io\"
" "$CONFIG"

# Update node IPs — assign sequential IPs starting at .11
NODE_COUNT=$(yq '.nodes | length' "$CONFIG")
for ((i = 0; i < NODE_COUNT; i++)); do
    yq -i ".nodes[${i}].ip = \"${NEW_MGMT_BASE}.$((11 + i))\"" "$CONFIG"
done

# Update URL fields that embed the MGMT server IP
if [[ "$SKIP_ARTIFACTS" == false ]]; then
    IP_RE="[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+"
    yq -i "
      (.artifact_server_url                    | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\") |
      (.harvester_iso_url                      | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\") |
      (.harvester_kernel_url                   | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\") |
      (.harvester_ramdisk_url                  | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\") |
      (.harvester_rootfs_url                   | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\") |
      (.harvester.vms.ubuntu.image_url         | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\") |
      (.harvester.vms.opensuse.image_url       | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\") |
      (.harvester.registry_mirrors[0].endpoint | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\") |
      (.tests.upgrade.iso_url                  | select(. != null)) |= sub(\"${IP_RE}\", \"${NEW_MGMT_BASE}.1\")
    " "$CONFIG"
fi

echo "Updated $CONFIG"
echo "  NAT:  ${NEW_NAT_NAME}  ${NAT_SUBNET}"
echo "  MGMT: ${NEW_MGMT_NAME} ${MGMT_SUBNET}"
echo "  DATA: ${NEW_DATA_NAME} ${DATA_SUBNET}"
