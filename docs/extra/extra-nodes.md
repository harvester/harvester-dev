# Extra nodes (VMs)

Extra nodes are general-purpose VMs booted from a qcow2 cloud image. Each VM gets two network interfaces:

- **enp1s0** — DHCP from `hvst-libvirt` (NAT, internet access)
- **enp2s0** — DHCP from `hvst-mgmt` (access to the Harvester cluster)

## Configuration

Add an `extra_nodes` section to `config.yaml`:

```yaml
extra_nodes:
  - name: dev1
    enabled: true   # define the libvirt domain
    running: true   # start the domain automatically
    cpu: 4
    memory: 4       # GiB
    image_url: "./artifacts/images/noble-server-cloudimg-amd64.img"
    image_vol_size: 100  # GiB
    password: a     # optional: set login password via cloud-init
    # Optional: cloud-init network config. Interface names vary by OS/image.
    # enp1s0 = hvst-libvirt (NAT), enp2s0 = hvst-mgmt. Omit to skip network setup.
    network_config:
      version: 2
      ethernets:
        enp1s0:
          dhcp4: true
        enp2s0:
          dhcp4: true
```

## Fields

| Field | Required | Description |
|---|---|---|
| `name` | yes | VM name (prefixed with `domain_prefix`) |
| `enabled` | yes | When `false`, the domain is not created |
| `running` | no | Start the domain on `terraform apply` (default: `false`) |
| `cpu` | no | vCPU count (default: 2) |
| `memory` | no | RAM in GiB (default: 4) |
| `image_url` | yes | HTTP URL or local path to a qcow2 cloud image |
| `image_vol_size` | yes | OS disk size in GiB (thin-provisioned over the base image) |
| `user` | no | SSH user for the generated `ssh_config` (default: `ubuntu`) |
| `password` | no | Login password injected via cloud-init |
| `network_config` | no | cloud-init [network config v2](https://docs.cloud-init.io/en/latest/reference/network-config-format-v2.html). Omit to skip network setup. |
