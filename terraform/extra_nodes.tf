resource "libvirt_volume" "extra_node_base" {
  for_each = local.extra_nodes

  name = "${each.value.name}-base.qcow2"
  pool = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = each.value.image_url
    }
  }
}

resource "libvirt_volume" "extra_node_disk" {
  for_each = local.extra_nodes

  name     = "${each.value.name}-disk.qcow2"
  pool     = "default"
  capacity = each.value.image_vol_size * 1073741824

  backing_store = {
    path = libvirt_volume.extra_node_base[each.key].path
    format = {
      type = "qcow2"
    }
  }

  target = {
    format = {
      type = "qcow2"
    }
    permissions = {
      owner = data.external.qemu_ids.result.uid != "" ? data.external.qemu_ids.result.uid : null
      group = data.external.qemu_ids.result.gid != "" ? data.external.qemu_ids.result.gid : null
      mode  = "0764"
    }
  }
}

resource "libvirt_cloudinit_disk" "extra_node_cloudinit" {
  for_each = local.extra_nodes

  name = "${each.value.name}-cloudinit.iso"

  user_data = templatefile("${path.module}/templates/extra/user_data.yaml.tftpl", {
    vm_password = each.value.password
    ssh_pubkey  = file("${path.module}/../${local.config.admin.pubkey_path}")
    hostname    = each.value.name
  })

  network_config = each.value.network_config != null ? yamlencode(each.value.network_config) : null

  meta_data = templatefile("${path.module}/templates/extra/meta_data.yaml.tftpl", {
    hostname = each.value.name
  })
}

resource "libvirt_domain" "extra_node" {
  for_each = local.extra_nodes

  name        = each.value.name
  description = "Source: ${abspath(path.module)}"
  type        = "kvm"
  memory      = each.value.memory
  memory_unit = "GiB"
  vcpu        = each.value.cpu

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
    apic = {}
    pae  = true
  }

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  running = each.value.running

  devices = {
    disks = [
      {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = "default"
            volume = libvirt_volume.extra_node_disk[each.key].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device = "cdrom"
        source = {
          file = {
            file = libvirt_cloudinit_disk.extra_node_cloudinit[each.key].path
          }
        }
        target = {
          dev = "sdb"
          bus = "sata"
        }
        read_only = true
      }
    ]
    serials  = [{ target = { type = "isa-serial", port = 0 } }]
    consoles = [{ target = { type = "serial", port = 0 } }]
    interfaces = [
      {
        model  = { type = "virtio" }
        source = { network = { network = libvirt_network.hvst_libvirt.name } }
        wait_for_ip = { source = "lease" }
      },
      {
        model  = { type = "virtio" }
        source = { network = { network = libvirt_network.hvst_mgmt.name } }
      }
    ]
    channels = [
      {
        source = { unix = {} }
        target = { virt_io = { name = "org.qemu.guest_agent.0" } }
      }
    ]
    graphics = [{ vnc = { listen = "0.0.0.0" } }]
  }
}

data "libvirt_domain_interface_addresses" "extra_node" {
  for_each = local.extra_nodes
  domain   = libvirt_domain.extra_node[each.key].uuid
  source   = "any"
}
