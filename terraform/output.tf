output "admin_first_interface_ip" {
  description = "First interface IP address of the admin node"
  value       = var.admin_node_count > 0 ? try(data.libvirt_domain_interface_addresses.admin[0].interfaces[0].addrs[0].addr, null) : null
}

output "rancher_first_interface_ip" {
  description = "First interface IP address of the rancher node"
  value       = var.rancher_node_count > 0 ? try(data.libvirt_domain_interface_addresses.rancher[0].interfaces[0].addrs[0].addr, null) : null
}

output "extra_node_ips" {
  description = "First interface IP addresses of extra nodes"
  value = {
    for k, v in data.libvirt_domain_interface_addresses.extra_node : k => try(v.interfaces[0].addrs[0].addr, null)
  }
}

# Generate SSH config file for convenient access to VMs
resource "local_file" "ssh_config" {
  filename        = "${path.module}/../state/ssh_config"
  file_permission = "0644"
  content = templatefile("${path.module}/templates/ssh_config.tftpl", {
    admin_ip       = local.admin_ip
    rancher_ip     = split("/", local.config.rancher.interfaces[0].ip)[0]
    rancher_user   = local.config.rancher.user
    nodes          = local.config.nodes
    ssh_key_path   = "${abspath(path.module)}/../${local.config.admin.private_key_path}"
    extra_nodes     = local.extra_nodes
    extra_node_ips  = { for k, v in data.libvirt_domain_interface_addresses.extra_node : k => try(v.interfaces[0].addrs[0].addr, null) }
  })
}