terraform {
  required_version = ">= 0.13"
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = "1.7.1"
    }
  }
}

provider "harvester" {
  kubeconfig = "${path.module}/../../../kubeconfig"
}

locals {
  config = yamldecode(file("../../../config.yaml"))

  pubkey = file("../../../${local.config.harvester.pubkey_path}")
}

resource "harvester_image" "ubuntu" {
  name      = "ubuntu"
  namespace = local.config.harvester.namespace

  display_name = "ubuntu"
  source_type  = "download"
  url          = local.config.harvester.vms.ubuntu.image_url
}

resource "harvester_image" "opensuse" {
  name      = "opensuse"
  namespace = local.config.harvester.namespace

  display_name = "opensuse"
  source_type  = "download"
  url          = local.config.harvester.vms.opensuse.image_url
}

resource "harvester_ssh_key" "mysshkey" {
  name      = "hvst-dev-pubkey"
  namespace = local.config.harvester.namespace

  public_key = local.pubkey
}

resource "harvester_clusternetwork" "cluster-vlan" {
  name = local.config.harvester.cluster_network.name
}

resource "harvester_vlanconfig" "cluster-vlanconfig" {
  name = local.config.harvester.cluster_network.uplink

  cluster_network_name = harvester_clusternetwork.cluster-vlan.name

  uplink {
    nics = [
      local.config.harvester.cluster_network.uplink,
    ]

    bond_mode = "active-backup"
    mtu       = 1500
  }

#  node_selector = {
#    "kubernetes.io/hostname" : "node1"
#  }
}

resource "harvester_network" "hvst-dev-vlan" {
  name      = "hvst-dev-vlan"
  namespace = local.config.harvester.namespace

  vlan_id = local.config.harvester.vm_network.vlan_id

  # route_mode           = "auto"
  # route_dhcp_server_ip = ""

  cluster_network_name = harvester_clusternetwork.cluster-vlan.name
  depends_on = [
    harvester_vlanconfig.cluster-vlanconfig
  ]
}

resource "harvester_virtualmachine" "ubuntu" {
  count = local.config.harvester.vms.ubuntu.count
  name                 = "ubuntu-${count.index}"
  namespace            = local.config.harvester.namespace
  restart_after_update = true

  description = "test ubuntu"
  tags = {
    ssh-user = "ubuntu"
  }

  cpu    = local.config.harvester.vms.ubuntu.cpu
  memory = "${local.config.harvester.vms.ubuntu.memory_in_mib}Mi"

  efi         = true
  secure_boot = true

  run_strategy = "RerunOnFailure"
  hostname     = "ubuntu"
  machine_type = "q35"

#  ssh_keys = [
#    harvester_ssh_key.mysshkey.id
#  ]

  network_interface {
    name           = "nic-1"
    network_name = harvester_network.hvst-dev-vlan.id

    wait_for_lease = true
  }

  disk {
    name       = "rootdisk"
    type       = "disk"
    size       = "${local.config.harvester.vms.ubuntu.disk_size}Gi"
    bus        = "virtio"
    boot_order = 1

    image       = harvester_image.ubuntu.id
    auto_delete = true
  }

#  disk {
#    name        = "emptydisk"
#    type        = "disk"
#    size        = "20Gi"
#    bus         = "virtio"
#    auto_delete = true
#  }

  cloudinit {
    user_data    = <<-EOF
      #cloud-config
      password: a
      chpasswd:
        expire: false
      ssh_pwauth: true
      package_update: true
      packages:
        - qemu-guest-agent
      runcmd:
        - - systemctl
          - enable
          - '--now'
          - qemu-guest-agent 
      ssh_authorized_keys:
        - >-
          ${local.pubkey}
      EOF
    network_data = ""
  }
}

resource "harvester_virtualmachine" "opensuse" {
  count = local.config.harvester.vms.opensuse.count
  name                 = "opensuse-${count.index}"
  namespace            = local.config.harvester.namespace
  restart_after_update = true

  description = "test opensuse"
  tags = {
    ssh-user = "opensuse"
  }

  cpu    = local.config.harvester.vms.opensuse.cpu
  memory = "${local.config.harvester.vms.opensuse.memory_in_mib}Mi"

  efi         = true
  secure_boot = true

  run_strategy = "RerunOnFailure"
  hostname     = "opensuse"
  machine_type = "q35"

#  ssh_keys = [
#    harvester_ssh_key.mysshkey.id
#  ]

  network_interface {
    name           = "nic-1"
    network_name = harvester_network.hvst-dev-vlan.id

    wait_for_lease = true
  }

  disk {
    name       = "rootdisk"
    type       = "disk"
    size       = "${local.config.harvester.vms.opensuse.disk_size}Gi"
    bus        = "virtio"
    boot_order = 1

    image       = harvester_image.opensuse.id
    auto_delete = true
  }

#  disk {
#    name        = "emptydisk"
#    type        = "disk"
#    size        = "20Gi"
#    bus         = "virtio"
#    auto_delete = true
#  }

  cloudinit {
    user_data    = <<-EOF
      #cloud-config
      password: a
      chpasswd:
        expire: false
      ssh_pwauth: true
      package_update: true
      ssh_authorized_keys:
        - >-
          ${local.pubkey}
      EOF
    network_data = ""
  }
}
