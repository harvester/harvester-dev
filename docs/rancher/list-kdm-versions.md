# List Kubernetes versions supported by Rancher

`op:rancher-list-kdm-versions` lists the RKE2/K3s versions that the Rancher version in `.rancher.version` offers for guest clusters.

Rancher reads this list from Kontainer Driver Metadata (KDM) at `https://releases.rancher.com/kontainer-driver-metadata/release-v2.<minor>/data.json`. It offers a release only if the Rancher version falls inside the release's `minChannelServerVersion`/`maxChannelServerVersion` range. The task applies the same filter. It doesn't need a running Rancher.

```sh
task op:rancher-list-kdm-versions                         # latest patch of each minor (like the UI)
task op:rancher-list-kdm-versions -- --all                # every compatible patch
task op:rancher-list-kdm-versions -- --distro rke2        # only RKE2 (or k3s)
task op:rancher-list-kdm-versions -- --version v2.13.2    # another Rancher version
KDM_URL=https://releases.rancher.com/kontainer-driver-metadata/dev-v2.15/data.json \
  task op:rancher-list-kdm-versions -- --version v2.15.0-alpha1
```

KDM is fetched at runtime, so new patch releases can appear without a Rancher upgrade.
