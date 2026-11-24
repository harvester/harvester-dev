# Create a VM node and boot from an ISO

* Prepare the ISO and place it on the host (e.g. `/tmp/harvester.iso`). The `qemu` user must be able to read the file and its directories.
* Edit `config.yaml`. Only `file` and `count` are required; everything else has sensible defaults.

  ```yaml
  iso_boot:
    file: /tmp/harvester.iso
    use_pool: false
    count: 1
    cpu: 8
    memory: 16
    vnc_port_start: 5961
    disks:
      - 500G
      - 500G
  ```

* Set `use_pool: true` if `qemu` can't read the ISO's path (e.g. a `0700` home directory). The ISO is copied into the libvirt `default` pool, and copied again by `task admin-up` when the file changes. Each copy writes the full ISO to disk.

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

* To wipe the data disks and boot the ISO nodes into the installer again, without rebuilding the infra or copying the ISO again:

  ```bash
  task op:iso-boot-nodes-reinstall
  ```

The VMs boot from their attached ISO first, then fall back to the data disks. Connect to the console via VNC — port for node `N` is `5960 + N`. The admin node runs an internal DHCP server so you can use DHCP during installation.

> **Note:** You may need to open the VNC ports in your firewall (e.g. `5961`, `5962`, …).
