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

# Size and mtime of the ISO file, so a rebuilt ISO at the same path
# replaces the pool copy. Hashing the file would read it on every plan.
data "external" "iso_boot_file_stat" {
  count = local.iso_boot_use_pool ? 1 : 0

  program = ["sh", "-c", <<-EOT
    st=$(stat -L -c '%s-%Y' "$1") || exit 1
    echo "{\"stat\":\"$st\"}"
  EOT
    , "sh", local.iso_boot_file
  ]
}

resource "terraform_data" "iso_boot_file_stat" {
  count = local.iso_boot_use_pool ? 1 : 0

  input = data.external.iso_boot_file_stat[0].result.stat
}

# Copy of the ISO in the default pool, shared read-only by all iso_boot
# nodes (iso_boot.use_pool)
resource "libvirt_volume" "iso_boot_cdrom" {
  count = local.iso_boot_use_pool ? 1 : 0

  name = "${local.prefix}-iso-boot.iso"
  pool = "default"

  target = {
    # libvirt detects ISO 9660 content as "iso"; "raw" makes the
    # provider report an inconsistent result after upload
    format = {
      type = "iso"
    }
    permissions = {
      owner = data.external.qemu_ids.result.uid != "" ? data.external.qemu_ids.result.uid : null
      group = data.external.qemu_ids.result.gid != "" ? data.external.qemu_ids.result.gid : null
      mode  = "0644"
    }
  }

  create = {
    content = {
      url = local.iso_boot_file
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.iso_boot_file_stat[0]]
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
          file = local.iso_boot_use_pool ? null : {
            file = each.value.iso_file
          }
          volume = local.iso_boot_use_pool ? {
            pool   = "default"
            volume = libvirt_volume.iso_boot_cdrom[0].name
          } : null
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
      {
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.hvst_mgmt.name
          }
        }
      },
      {
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.hvst_data.name
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
