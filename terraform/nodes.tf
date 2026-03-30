# Get qemu user/group IDs from the system
data "external" "qemu_ids" {
  program = ["sh", "-c", <<-EOT
    owner_name="${try(local.config.node_disk_owner, "qemu")}"
    group_name="${try(local.config.node_disk_group, "qemu")}"
    uid=$(id -u "$owner_name" 2>/dev/null || echo "")
    gid=$(getent group "$group_name" 2>/dev/null | cut -d: -f3 || echo "")
    echo "{\"uid\":\"$uid\",\"gid\":\"$gid\"}"
  EOT
  ]
}

# Create disk volumes for each node
resource "libvirt_volume" "node_disk" {
  for_each = local.nodes

  name     = "${each.value.name}-disk.qcow2"
  pool     = "default"
  capacity = each.value.disk_size_bytes

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

# Create libvirt domains for each node
resource "libvirt_domain" "node" {
  for_each = local.nodes

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
    type            = "hvm"
    type_arch       = "x86_64"
    type_machine    = "q35"
    loader          = "/usr/share/qemu/ovmf-x86_64-4m.bin"
    loader_readonly = "yes"
    boot_devices = [
      {
        dev = "hd"
      },
      {
        dev = "network"
      }
    ]
    # some machines requires the boot menu to be enabled to boot from the network
    boot_menu = {
      enable = "yes"
      timeout = 3000
    }
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
            volume = libvirt_volume.node_disk[each.key].name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
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

    interfaces = [
      for iface in each.value.interfaces : {
        model = {
          type = "virtio"
        }
        source = {
          bridge = {
            bridge = iface.host_bridge
          }
        }
        mac = {
          address = iface.mac
        }
      }
    ]

    channels = [
      {
        source = {
          unix = {}
        }
        target = {
          virt_io = {
            name = "org.qemu.guest_agent.0"
            #     state = "connected"
          }
        }
      }
    ]

    graphics = [
      {
        vnc = {
          listen   = "0.0.0.0"
          port     = each.value.vnc_port
          autoport = "no"
        }
      }
    ]
  }
}
