
variable "rancher_node_count" {
  description = "Number of rancher nodes to create"
  type        = number
  default     = 1
}

variable "rancher_vm_password" {
  description = "Rancher VM Password"
  type        = string
  sensitive   = true
  default     = "a"
}

resource "libvirt_volume" "rancher_base" {
  name = "${local.prefix}-rancher-base.qcow2"
  pool = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = local.config.rancher.image_url
    }
  }
}

resource "libvirt_volume" "rancher_disk" {
  name     = "${local.prefix}-rancher-disk.qcow2"
  pool     = "default"
  capacity = local.config.rancher.image_vol_size * 1073741824

  backing_store = {
    path = libvirt_volume.rancher_base.path
    format = {
      type = "qcow2"
    }
  }


  target = {
    format = {
      type = "qcow2"
    }
    permissions = {
      owner = "452"
      group = "452"
      mode  = "0744"
    }
  }
}

resource "libvirt_cloudinit_disk" "rancher_cloudinit" {
  name = "rancher-cloudinit.iso"

  user_data = templatefile("${path.module}/templates/rancher/user_data-debian.yaml.tftpl", {
    vm_password            = var.rancher_vm_password
    ssh_pubkey             = file("${path.module}/../${local.config.admin.pubkey_path}")
  })

  network_config = templatefile("${path.module}/templates/rancher/network_config-debian.yaml.tftpl", {
    vm_interfaces = local.config.rancher.interfaces
  })

  meta_data = templatefile("${path.module}/templates/rancher/meta_data.yaml.tftpl", {})
}

resource "libvirt_domain" "harvester-dev-rancher" {
  count       = var.rancher_node_count
  name        = "${local.prefix}-rancher"
  description = "Source: ${abspath(path.module)}"
  type        = "kvm"
  memory      = local.config.rancher.memory_in_mib
  memory_unit = "MiB"
  vcpu        = local.config.rancher.cpu

  cpu = {
    mode = "host-passthrough"
  }

  features = {
    acpi = true
    apic = {
    }
    pae = true
  }

  # Workaround (disable AppArmor confinement for this VM) if host policy is not configured yet:
  # sec_label = [
  #   {
  #     model = "apparmor"
  #     type  = "none"
  #   }
  # ]

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  running = false

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
            volume = libvirt_volume.rancher_disk.name
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
            file = libvirt_cloudinit_disk.rancher_cloudinit.path
          }
        }
        target = {
          dev = "sdb"
          bus = "sata"
        }
        read_only = true
      }
    ]
    serials = [
      {
        target = {
          type = "isa-serial"
          port = 0
        }
      }
    ]
    consoles = [
      {
        target = {
          type = "serial"
          port = 0
        }
      }
    ]
    interfaces = concat([
      {
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.harvester_dev.name
          }
        }
        wait_for_ip = {
          source = "lease"
        }
      }
      ], [
      for iface in local.config.rancher.interfaces : {
        model = {
          type = "virtio"
        }
        source = {
          bridge = {
            bridge = iface.bridge
          }
        }
      }
    ])
    channels = [
      {
        source = {
          unix = {
          }
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
            # state = "connected"
          }
        }
      }
    ]
    graphics = [
      {
        vnc = {
          listen = "0.0.0.0"
        }
      }
    ]
  }
}

data "libvirt_domain_interface_addresses" "rancher" {
  count  = var.rancher_node_count
  domain = libvirt_domain.harvester-dev-rancher[count.index].uuid
}
