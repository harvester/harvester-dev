terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.6"
    }
  }
}

variable "admin_node_count" {
  description = "Number of admin nodes to create"
  type        = number
  default     = 1
}

variable "admin_vm_password" {
  description = "Password used by cloud-init for vm_username"
  type        = string
  sensitive   = true
  default     = "a"
}

# Configure the Libvirt Provider
provider "libvirt" {
  uri = local.config.provider.libvirt.uri
}

resource "libvirt_network" "harvester_dev" {
  # count = 1
  name      = "harvester-dev"
  autostart = true

  forward = {
    mode = "nat"
  }

  ips = [
    {
      family  = "ipv4"
      address = "192.168.123.1"
      netmask = "255.255.255.0"
      dhcp = {
        ranges = [
          {
            start = "192.168.123.100"
            end   = "192.168.123.254"
          }
        ]
      }
    }
  ]
}

resource "libvirt_volume" "admin_base" {
  name = "${local.prefix}-admin-base.qcow2"
  pool = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = local.config.admin.image_url
    }
  }
}

resource "libvirt_volume" "admin_disk" {
  name     = "${local.prefix}-admin-disk.qcow2"
  pool     = "default"
  capacity = local.config.admin.image_vol_size * 1073741824

  backing_store = {
    path = libvirt_volume.admin_base.path
    format = {
      type = "qcow2"
    }
  }


  target = {
    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "admin_cloudinit" {
  name = "admin-cloudinit.iso"

  user_data = templatefile("${path.module}/templates/admin/user_data-alpine.yaml.tftpl", {
    vm_password = var.admin_vm_password
    dnsmasq_config = templatefile("${path.module}/templates/admin/dnsmasq.conf.tftpl", {
      nodes            = local.nodes
      admin_ip         = local.admin_ip
      admin_interfaces = local.admin_interfaces
      vip               = local.config.vip
      vip_mac           = local.config.vip_mac
      vip_mode          = local.config.vip_mode
      dns_servers      = local.config.admin.dhcp.dns_servers
    })
    nginx_config           = templatefile("${path.module}/templates/admin/nginx-location.conf.tftpl", {})
    config                 = local.config
    nodes                  = local.nodes
    admin_ip               = local.admin_ip
    admin_interfaces       = local.admin_interfaces
    ssh_pubkey             = file("${path.module}/../${local.config.admin.pubkey_path}")
    harvester_node_configs = local.harvester_node_configs
  })

  network_config = templatefile("${path.module}/templates/admin/network_config-alpine.yaml.tftpl", {
    admin_interfaces = local.admin_interfaces
  })

  meta_data = templatefile("${path.module}/templates/admin/meta_data.yaml.tftpl", {})
}

resource "libvirt_volume" "admin_cloudinit_disk" {
  name   = "admin-cloudinit-disk"
  pool   = "default"
  target = {
    format = {
      type = "iso"
    }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.admin_cloudinit.path
    }
  }
}

resource "libvirt_domain" "harvester-dev-admin" {
  count       = var.admin_node_count
  name        = "${local.prefix}-admin"
  description = "Source: ${abspath(path.module)}"
  type        = "kvm"
  memory      = local.config.admin.memory_in_mib
  memory_unit = "MiB"
  vcpu        = local.config.admin.cpu

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

  running = true

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
            volume = libvirt_volume.admin_disk.name
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
          volume = {
            pool   = "default"
            volume = libvirt_volume.admin_cloudinit_disk.name
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
      for iface in local.admin_interfaces : {
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

data "libvirt_domain_interface_addresses" "admin" {
  count  = var.admin_node_count
  domain = libvirt_domain.harvester-dev-admin[count.index].uuid
  source = "any"
}
