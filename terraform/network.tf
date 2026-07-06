# ==============================================================================
#                          Network Topology
# ==============================================================================
#
# +---------------+
# |    bridge     |
# | hvst-libvirt  |============== hvst-libvirt (192.168.123.0/24) ==============
# | 192.168.123.1 |              |                                     |
# +---------------+              |                                     |
#                        +-------0--------+                   +--------0-------+
#                        |   Admin Node   |                   |  Rancher Node  |
#                        | eth0: libvirt  |                   | eth0: libvirt  |
#                        | eth1: mgmt     |                   | eth1: mgmt     |
#                        | eth2: data     |                   |                |
#                        +----2------1----+                   +--------1-------+
# +---------------+           |      |                                 |
# |     bridge    |           |      |                                 |
# |   hvst-mgmt   |============== hvst-mgmt (10.0.10.0/24) =====================
# |    10.0.10.1  |           |       |            |            |          |
# +---------------+           |       |            |            |          |
#                             |  +----0-----+ +----0-----+ +----0-----+
#                             |  |  Node 1  | |  Node 2  | |  Node 3  |  ...
#                             |  |10.0.10.11| |10.0.10.12| |10.0.10.13|
#                             |  |          | |          | |          |
#                             |  +----1-----+ +----1-----+ +----1-----+
# +---------------+           |       |            |            |          |
# |     bridge    |           |       |            |            |          |
# |   hvst-data   |============== hvst-data (10.0.11.0/24) =====================
# |    10.0.11.1  |              storage / nested VMs
# +---------------+
#
#
# Networks:
#   hvst-libvirt  NAT; host libvirt dnsmasq assigns eth0 IPs for Admin/Rancher.
#                 Admin and Rancher egress through host hvst-libvirt bridge.
#                 Admin node runs dnsmasq on eth1/eth2 to serve mgmt/data IPs.
#                 VM nodes are air-gapped by default; enable egress with:
#                   task op:admin-enable-egress
#
#   hvst-mgmt     Inter-node traffic; non-subnet routes go through admin node.
#                 hvst-mgmt bridge: the IP on it allows host to connect to the harvester nodes.
#
#   hvst-data     Storage and nested VM traffic.
#                 Nested VMs get IPs from admin dnsmasq; egress follows admin setting.
#

resource "libvirt_network" "hvst_libvirt" {
  # count = 1
  name      = local.config.networks.nat.bridge_name
  autostart = true

  forward = {
    mode = "nat"
  }

  bridge = {
    name = local.config.networks.nat.bridge_name
  }

  ips = [
    {
      family  = "ipv4"
      address = local.config.networks.nat.bridge_ip
      netmask = local.config.networks.nat.netmask
      dhcp = {
        ranges = [
          {
            start = local.config.networks.nat.dhcp_start
            end   = local.config.networks.nat.dhcp_end
          }
        ]
      }
    }
  ]
}

resource "libvirt_network" "hvst_mgmt" {
  name      = local.config.networks.mgmt.bridge_name
  autostart = true

  forward = {
    mode = "open"
  }

  bridge = {
    name = local.config.networks.mgmt.bridge_name
  }

  ips = [
    {
      family  = "ipv4"
      address = local.config.networks.mgmt.bridge_ip
      netmask = local.config.networks.mgmt.netmask
    }
  ]
}

resource "libvirt_network" "hvst_data" {
  name      = local.config.networks.data.bridge_name
  autostart = true

  bridge = {
    name = local.config.networks.data.bridge_name
  }

  ips = [
    {
      family  = "ipv4"
      address = local.config.networks.data.bridge_ip
      netmask = local.config.networks.data.netmask
    }
  ]
}
