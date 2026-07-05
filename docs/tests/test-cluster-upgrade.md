# op:test-cluster-upgrade

Configure the `.tests.upgrade` section in `config.yaml`:

```yaml
tests:
  upgrade:
    iso_url: http://10.0.20.1/harvester/harvester.iso
    skip_version_check: true
    parallel_preload: true
```

| Field | Description |
|-------|-------------|
| `iso_url` | URL of the ISO to upgrade to. |
| `skip_version_check` | Annotation hack to upgrade from a formal release (e.g. `v1.8.0`) to a dev build. |
| `parallel_preload` | Load images in parallel during upgrade; see [upgrade-config](https://docs.harvesterhci.io/v1.8/advanced/index#upgrade-config). |


And upgrade the Harvester cluster by:

```
task op:test-cluster-upgrade
```
