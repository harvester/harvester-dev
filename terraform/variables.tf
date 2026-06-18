# Load node configuration from YAML
locals {
  config = yamldecode(file("${path.module}/../config.yaml"))

  prefix = local.config.provider.domain_prefix

  # Extract admin IP (strip subnet mask)
  admin_ip = split("/", local.config.admin.interfaces[0].ip)[0]

  # Transform admin interfaces for easier access
  admin_interfaces = local.config.admin.interfaces

  # Transform nodes array into a map with index as key for for_each
  nodes = {
    for idx, node in local.config.nodes : idx => merge(node, {
      name  = "${local.prefix}-node${idx + 1}"
      disks = try(node.disks, ["500G"])
    })
  }

  # Precompute disk volume configs: one entry per (node, disk_index) pair
  node_disk_entries = flatten([
    for node_key, node in local.nodes : [
      for i in range(length(node.disks)) : {
        key   = "${node.name}-disk${i + 1}"
        name  = "${node.name}-disk${i + 1}.qcow2"
        bytes = tonumber(replace(node.disks[i], "G", "")) * 1073741824
      }
    ]
  ])

  # Render Harvester node configuration files
  harvester_node_configs = {
    for idx, node in local.config.nodes : "${local.prefix}-node${idx + 1}" => templatefile("${path.module}/templates/admin/harvester-config.yaml.tftpl", {
      mode     = idx == 0 ? "create" : "join"
      token    = local.config.token
      hostname = "node${idx + 1}"
      hwaddr   = node.interfaces[0].mac
      iso_url  = local.config.harvester_iso_url
      vip      = local.config.vip
      vip_mac  = local.config.vip_mac
      vip_mode = local.config.vip_mode
      role     = node.role
      password = local.config.node_password
      ssh_keys = concat([trimspace(file("${path.module}/../${local.config.admin.pubkey_path}"))], try(local.config.node_additional_keys, []))
    })
  }

  # Transform iso_boot config into a map with index as key for for_each
  iso_nodes = {
    for idx in range(try(local.config.iso_boot.count, 0)) : idx => {
      name       = "${local.prefix}-iso-node${idx + 1}"
      cpu        = try(local.config.iso_boot.cpu, 2)
      memory     = try(local.config.iso_boot.memory, 4)
      iso_file   = try(local.config.iso_boot.file, "")
      disks      = try(local.config.iso_boot.disks, ["50G", "50G"])
      interfaces = try(local.config.iso_boot.interfaces, [])
      vnc_port   = try(local.config.iso_boot.vnc_port_start, 5961) + idx
    }
  }

  # Precompute disk volume configs: one entry per (node, disk_index) pair
  iso_disk_entries = flatten([
    for node in local.iso_nodes : [
      for i in range(length(node.disks)) : {
        key   = "${node.name}-disk${i + 1}"
        name  = "${node.name}-disk${i + 1}.qcow2"
        bytes = tonumber(replace(node.disks[i], "G", "")) * 1073741824
      }
    ]
  ])
}
