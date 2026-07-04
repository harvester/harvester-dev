# Provision Rancher and import Harvester cluster to it

Ensure you have sane configuration in the `.rancher` section. Set the `enabled` field to `true`.

Import configurable values are:
- `k3s_version`: The k3s version to provision.
- `repo`: Rancher chart repo.
- `version`: The rancher version you'd like to provision.

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
```

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