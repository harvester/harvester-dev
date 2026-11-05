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


To set `iso_url`, use `task select-upgrade-iso -- VERSION` for an ISO in
`./artifacts/isos`, or `task select-upgrade-remote-iso -- [--proxy] VERSION`
for a release server (see [Artifact server](../artifact-server.md#boot-or-upgrade-from-a-remote-release)).

And upgrade the Harvester cluster by:

```
task op:test-cluster-upgrade
```
