

## Permission issue when not using the default image path `/var/lib/libvirt/images`

```
| Domain was defined but failed to start: internal error: process exited while connecting to monitor: 2026-03-29T13:58:32.157307Z qemu-system-x86_64: -blockdev
│ {"driver":"file","filename":"/mnt/vol1/libvirt_images/admin-disk.qcow2","node-name":"libvirt-1-storage","read-only":false}: Could not open '/mnt/vol1/libvirt_images/admin-disk.qcow2':
│ Permission denied
```

My case is AppArmor forbid the access to non default path. You can see DENIED logs in `/var/log/audit/audit.log`.
To fix the issue:

- Create file `/etc/apparmor.d/abstractions/libvirt-qemu.d/90-custom-storage` with the content:

    ```
    /mnt/vol1/libvirt_images/ r,
    /mnt/vol1/libvirt_images/** rwk,
    ```

    Replace the path accordingly.

- Restart AppArmor:

    ```
    systemctl reload apparmor
    systemctl restart apparmor
    ```

Note my system is OpenSUSE Tumbleweed, your mileage might varies.

## VM can't get IP

VM can't get IP and apparently blocked by firewall.

Swith firewall backend to iptables, edit `/etc/libvirt/network.conf`:

```
firewall_backend = "iptables"
```

Somehow nftables doesn't work very well.


## Libvirt Network can't be created

See ing this error when creating a network:

```
│ Network defined but failed to start: error from service: GDBus.Error:org.fedoraproject.FirewallD1.Exception: COMMAND_FAILED: '/sbin/ip6tables-restore -w -n' failed: ip6tables-restore:
│ line 26 failed: Index of insertion too big.
```

Same as previous issue, switch firewall backend to iptables fixes the issue for me.


## Default pool doesn't exist

Try create one manually:
```
sudo virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
sudo virsh pool-build default
sudo virsh pool-start default
sudo virsh pool-autostart default
```


## Artifact server has no permission to read served artifacts

If you have selinux enabled and saw the following log in the `hvst-artifacts-server` container:

```
2026/04/21 08:57:38 [error] 29#29: *1 open() "/usr/share/nginx/html/isos/harvester-v1.8.0-rc5/harvester-v1.8.0-rc5-vmlinuz-amd64" failed (13: Permission denied), client: 10.10.0.13, server: localhost, request: "GET /isos/harvester-v1.8.0-rc5/harvester-v1.8.0-rc5-vmlinuz-amd64 HTTP/1.1", host: "10.10.0.101:8787"
10.10.0.13 - - [21/Apr/2026:08:57:38 +0000] "GET /isos/harvester-v1.8.0-rc5/harvester-v1.8.0-rc5-vmlinuz-amd64 HTTP/1.1" 403 153 "-" "iPXE/2.0.0+ (g7e54e)" "-"
2026/04/21 08:57:40 [error] 30#30: *2 open() "/usr/share/nginx/html/isos/harvester-v1.8.0-rc5/harvester-v1.8.0-rc5-vmlinuz-amd64" failed (13: Permission denied), client: 10.10.0.12, server: localhost, request: "GET /isos/harvester-v1.8.0-rc5/harvester-v1.8.0-rc5-vmlinuz-amd64 HTTP/1.1", host: "10.10.0.101:8787"
```

You can relabel the artifact directories to make it work:

```
chcon -R -t container_file_t artifacts
```

## Fail to undefine admin domain when running `task clean`

If your host reboot and you see this:
```
╷
│ Error: Failed to Undefine Domain
│
│ Failed to undefine domain: Requested operation is not valid: Refusing to undefine while domain managed save image exists
```

Thatr's probably because the systemd `libvirt-guests.service` service suspend the admin VM during shutdown.
You can shutdown VMs rather than suspend VMs by editting `/etc/sysconfig/libvirt-guests` and add:

```
ON_SHUTDOWN="shutdown"
```

Note, this is a global control flag. The settings apply to all libvirt managed VMs on the host.
