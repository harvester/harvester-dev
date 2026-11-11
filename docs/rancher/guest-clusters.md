# Create guest Ccusters

Refer to the [doc](./provisioning-and-import.md) on how to provision Rancher and import Harvester cluster first.

Edit `.harvester` sections in `config.yaml`. Check network vlan settings. If you don't want some testing VMs to be provisioned, just set `count` to 0.

Bootstrap harvester. This will create images and networks:

```bash
task op:harvester-bootstrap
```

To configure guest clusters, edit `.guest_clusters` in `config.yaml`. You can disable a cluster by setting `.enabled` to `false`. 

To find the latest Kubernetes versions your Rancher version supports for guest clusters, run:

```bash
task op:rancher-list-kdm-versions
```

See [List Kubernetes versions supported by Rancher](./list-kdm-versions.md) for more options.

To set `.kubernetes_version` of all guest clusters to the latest supported version, pass the distro (`rke2` or `k3s`, default `rke2`):

```bash
task op:harvester-set-guest-clusters-k8s-version -- rke2
```

Then create guest clusters with:

```bash
task op:harvester-create-guest-clusters 
```
