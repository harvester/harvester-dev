# User guide

Check the main [README.md](../README.md) for how to bring a Harvester clusters locally.

## Nodes Tasks - Manage nodes

- [op:iso-boot-nodes-start](./nodes/iso-nodes.md) - Create VMs that boot from Harvesetr ISO directly. Useful if you want to test the manually ISO interative installation.

## Harvester Tasks - Manage Harvester clusters

- [op:harvester-configure-registries](harvester/configure-registries.md) — route image pulls through local mirror endpoints. The task configure the [`containerd-registry`](https://docs.harvesterhci.io/v1.8/advanced/index#containerd-registry) Harvseter setting.
- [op:harvester-patch-images](harvester/patch-harvester-images.md) — patch the harvester managed chart to use a custom image repository and tag, then wait for reconciliation.

## Rancher Tasks - Manager Rancher Manager and Guest clusters

- [Provisiong Rancher VM and import the Harvester cluster](./rancher/provisioning-and-import.md)
- [Create guest clsuters](./rancher/guest-clusters.md)

## Tests

- [op:test-cluster-upgrade](tests/test-cluster-upgrade.md) - upgrade Harvester cluster

## Extra nodes

- [Extra nodes](./extra/extra-nodes.md) - provision some extra nodes

## Troubleshooting

- [Troubleshooting](troubleshooting.md) — common issues with libvirt, AppArmor/SELinux, networking, and domain management

