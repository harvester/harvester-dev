# Create a VM node and boot from an ISO

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
  ```

* Provision infrastructure and boot the admin node:

  ```bash
  # teardown exisiting cluster if needed
  task clean

  # bring up the admin node
  task admin-up
  ```

* Boot the ISO nodes:

  ```bash
  task op:iso-boot-nodes-start
  ```

The VMs boot from their attached ISO first, then fall back to the data disks. Connect to the console via VNC — port for node `N` is `5960 + N`. The admin node runs an internal DHCP server so you can use DHCP during installation.

> **Note:** You may need to open the VNC ports in your firewall (e.g. `5961`, `5962`, …).
