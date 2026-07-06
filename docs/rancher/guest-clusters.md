# Create guest Ccusters

Refer to the [doc](./provisioning-and-import.md) on how to provision Rancher and import Harvester cluster first.

Edit `.harvester` sections in `config.yaml`. Check network vlan settings. If you don't want some testing VMs to be provisioned, just set `count` to 0.

Bootstrap harvester. This will create images and networks:

```bash
task op:harvester-bootstrap
```

To configure guest clusters, edit `.guest_clusters` in `config.yaml`. You can disable a cluster by setting `.enabled` to `false`. 

Then create guest clusters with:

```bash
task op:harvester-create-guest-clusters 
```
