# Provision Rancher and import Harvester cluster to it

## Configuration

Ensure you have sane configuration in the `.rancher` section. Set the `enabled` field to `true`.

Import configurable values are:
- `k3s_version`: The k3s version to provision.
- `repo`: Rancher chart repo.
- `version`: The rancher version you'd like to provision.
- `registry_mirrors` (optional): Registry mirrors (e.g., pull-through caches) for the Rancher `local` cluster (k3s). See the note below the example.

```yaml
rancher:
  enabled: true
  image_url: <path to debian image>
  image_vol_size: 50
  cpu: 4
  memory_in_mib: 8192
  interfaces:
    - ip: 10.8.0.5/24
  # Provisioning configuration
  k3s_version: v1.35.3+k3s1
  repo: https://releases.rancher.com/server-charts/stable
  version: v2.14.1
  bootstrap_password: password
  admin_password: "password1234"
  hostname: rancher.10.8.0.5.sslip.io
  registry_mirrors:
    - registry: docker.io
      endpoint: http://10.8.0.1:5000
```

`registry_mirrors` is rendered as k3s [`registries.yaml`](https://docs.k3s.io/installation/private-registry) for the Rancher `local` cluster only. It doesn't apply to guest clusters or the imported Harvester cluster; for Harvester, see [op:harvester-configure-registries](../harvester/configure-registries.md).

## Provision and import

Ensure you have a running Harvester cluster first.

```bash
# task clean if needed.
task up
```

The harvester cluster need to pull `rancher-agent` images from Internnet. Enable network access first:

```bash
task op:admin-enable-egress
```

Bring up Rancher and import Harvester
```bash
task op:rancher-up
task op:harvester-import
```