# harvester-dev


## Quick start

### Provision Rancher and import Harvester cluster to it

Ensure you have sane configuration in the `.rancher` section:

```yaml
rancher:
  image_url: <path to debian image>
  image_vol_size: 50
  cpu: 4
  memory_in_mib: 8192
  interfaces:
    - ip: 10.8.0.5/24
      bridge: br8
  # Provisioning configuration
  k3s_version: v1.35.3+k3s1
  repo: https://releases.rancher.com/server-charts/stable
  version: v2.14.1
  bootstrap_password: password
  admin_password: "password1234"
  hostname: rancher.10.8.0.5.sslip.io
```

Ensure you have a running Harvester cluster first.

```bash
task up
```

The harvester cluster will pull `rancher-agent` image that tied to the Rancher manager. Enable network access first:

```bash
task op:admin-enable-egress
```

Bring up Rancher and import Harvester
```bash
task op:rancher-up
task op:harvester-import
```

### Provision guest clusters

Refer to the previous section to import Harvester cluster into Rancher first.

Edit `.harvester` sections in `config.yaml`. Check network vlan settings. If you don't want some testing VMs to be provisioned, just set `count` to 0.

Bootstrap harvester. This will create some images and networks:

```bash
task op:harvester-bootstrap
```

To configure guest clusters, edit `.guest_clusters` in `config.yaml`. You can disable a cluster by setting `.enabled` to `false`. 

Then create guest clusters with:

```bash
task op:harvester-create-guest-clusters 
```


### Create a VM node and boot from an ISO

* Prepare the ISO and place it on the host (e.g. `/tmp/harvester.iso`). The `qemu` user must be able to read the file.
* Edit `config.yaml`. Only `file` and `count` are required; everything else has sensible defaults.

  ```yaml
  iso_boot:
    file: /tmp/harvester.iso
    count: 1
    cpu: 8
    memory: 16
    vnc_port_start: 5961
    disks:
      - 500G
      - 500G
    interfaces:
      - host_bridge: br10
      - host_bridge: br11
  ```

* Provision infrastructure and boot the admin node:

  ```bash
  task admin-up
  ```

* Boot the ISO nodes:

  ```bash
  task op:iso-boot-nodes-start
  ```

The VMs boot from their attached ISO first, then fall back to the data disks. Connect to the console via VNC — port for node `N` is `5960 + N`. The admin node runs an internal DHCP server so you can use DHCP during installation.

> **Note:** You may need to open the VNC ports in your firewall (e.g. `5961`, `5962`, …).
