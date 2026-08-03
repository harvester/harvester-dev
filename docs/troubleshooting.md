

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


## Node VMs can't get DHCP / PXE from the admin node (br_netfilter)

Node VMs boot into PXE but never get an IP from the admin node's dnsmasq — the leases
file on the admin node (`/var/lib/misc/dnsmasq.leases`) stays empty, and the libvirt
firewall backend fix above doesn't help.

A common root cause is the `br_netfilter` kernel module. When it's loaded and
`net.bridge.bridge-nf-call-iptables=1`, bridged (L2) traffic on `hvst-mgmt` /
`hvst-data` is pushed through iptables/nftables, and DHCP broadcasts
(`0.0.0.0` → `255.255.255.255`) can be silently dropped by a `FORWARD` DROP policy or
docker-inserted rules. This is common on hosts that also run docker or Kubernetes,
since those load `br_netfilter` and enable the sysctl. If your host runs docker, test
this first before digging into firewalld/UFW rules.

### Diagnose

Check whether the module is loaded and who configures it:

```bash
lsmod | grep br_netfilter
grep -rn br_netfilter /etc/modules-load.d/ /etc/sysctl.d/ /etc/sysconfig/ 2>/dev/null
sysctl net.bridge.bridge-nf-call-iptables
```

Watch DHCP on the admin VM's tap device while resetting a node:

```bash
sudo tcpdump -i <admin-vnet> -n port 67 or port 68   # on the host
virsh reset hvst-node1                               # in another terminal
```

Seeing DHCP DISCOVER on the tap device means L2 is fine and the packets are dropped by
netfilter. Seeing nothing at all is a different problem — check L2 flooding with
`bridge fdb show`.

To confirm the root cause, temporarily disable the bridge netfilter hooks and retry:

```bash
sudo sysctl net.bridge.bridge-nf-call-iptables=0
sudo sysctl net.bridge.bridge-nf-call-ip6tables=0
sudo sysctl net.bridge.bridge-nf-call-arptables=0
```

### Fix

First check whether the host itself runs Kubernetes components — this decides which fix
is safe:

```bash
systemctl list-units --type=service | grep -iE 'rke2|k3s|kubelet'
```

**Pure lab host (no K8s/RKE2/kubelet)** — persist the sysctls, e.g. in
`/etc/sysctl.d/99-hvst-bridge.conf`:

```
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-arptables = 0
```

Also pin the module load. `sysctl --system` runs early during boot; if `br_netfilter`
is not loaded yet, the keys don't exist and the settings are silently skipped — after a
reboot you're back to square one:

```bash
echo br_netfilter | sudo tee /etc/modules-load.d/br_netfilter.conf
```

**Host also running K8s/RKE2** — do NOT disable `bridge-nf-call-*` globally. kubelet
and the CNI need it enabled and will flip it back on startup anyway. Keep it at `1` and
explicitly allow DHCP on the bridge instead. Find which rule is dropping first (watch
which counter grows while a node retries DHCP):

```bash
sudo iptables -L FORWARD -n -v | grep -iE 'DROP|policy'
sudo nft list ruleset | grep -iE 'drop|reject|policy'
```

Then insert an accept rule for the bridge, e.g. with docker installed:

```bash
sudo iptables -I DOCKER-USER -i hvst-mgmt -o hvst-mgmt -p udp --dport 67:68 -j ACCEPT
```

> [!NOTE]
> The K8s/RKE2 host approach above is not verified yet — it follows the expected
> direction but hasn't been tested in a real environment. If you go through this path,
> please verify and update this section.

### Notes

- firewalld's `trusted` zone does not cover the nftables rules docker inserts, so
  adding the bridge to the trusted zone may appear to have no effect.
- On UFW hosts, forward rules for UDP 67/68 must not be bound to the DHCP server IP —
  DISCOVER is sent from `0.0.0.0` to `255.255.255.255` and would be silently blocked.


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
