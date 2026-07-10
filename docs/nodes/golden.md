# Golden images

Suppose you deploy a cluster, and you want a way to test it repeatedly. You can use the golden image feature to save the VM disks and restore them later. Thus you don't need to re-install from ISO again.

## Create a cluster

First create a cluster as usual: edit `config.yaml` and `task up`.

## Save the cluster to a golden image

```bash
task op:nodes-golden-create -- VERSION

# for example: task op:nodes-golden-create -- v1.8.1
```

**VERSION** is the name of the golden image set. You must provide it.

Optionally, pass `--timestamp TS` to record an arbitrary timestamp alongside the golden image (written to `timestamp` inside the golden version directory). This is used to track the source artifact's freshness, e.g. by [`golden-prepare.sh`](../../scripts/golden-prepare.sh):

```bash
task op:nodes-golden-create -- --timestamp TS VERSION
```

> [!NOTE]
> Golden images are stored under `<base_dir>/<repo_id>/<version>`:
> - `base_dir` defaults to `/var/lib/libvirt/images/golden`. Override it with `.golden.base_dir` in `config.yaml`.
> - `repo_id` isolates golden images per cluster and defaults to `.provider.domain_prefix`. Override it with `.golden.repo_id` in `config.yaml`.
> - You must ensure the user you are using has permission to create folders and files under the golden base directory. A quick guide is to add the current user to the group which generally owns libvirt images (for example, the `libvirt` group), and change the directory mode of `/var/lib/libvirt/images` with `chmod u=rwx,g=rwxs,o=rx /var/lib/libvirt/images`.


## Restore

Run the following command to restore a golden image. The cluster will be booted up and the script waits for it to be ready.

```bash
task op:nodes-destroy
task op:nodes-golden-restore-and-boot -- VERSION
```

## Clean a golden image

```bash
task op:nodes-golden-clean -- VERSION

# omit VERSION to remove all golden images for this repo_id
task op:nodes-golden-clean
```


