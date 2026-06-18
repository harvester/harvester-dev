# Create data disk volumes for each iso_boot node
resource "libvirt_volume" "iso_node_data_disk" {
  for_each = { for entry in local.iso_disk_entries : entry.key => entry }

  name     = each.value.name
  pool     = "default"
  capacity = each.value.bytes
  
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

# Create libvirt domains for iso_boot nodes (boot from ISO)
resource "libvirt_domain" "iso_node" {
  for_each = local.iso_nodes

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
        dev = "cdrom"
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
    disks = concat(
      [{
        device = "cdrom"
        readonly = true
        driver = {
          name = "qemu"
          type = "raw"
        }
        source = {
          file = {
            file = each.value.iso_file
          }
        }
        target = {
          dev      = "sda"
          bus      = "sata"
        }
      }],
      [for i in range(length(each.value.disks)) : {
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        source = {
          volume = {
            pool   = "default"
            volume = libvirt_volume.iso_node_data_disk["${each.value.name}-disk${i + 1}"].name
          }
        }
        target = {
          dev = "vd${substr("abcdefghijklmnopqrstuvwxyz", i, 1)}"
          bus = "virtio"
        }
      }]
    )

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
