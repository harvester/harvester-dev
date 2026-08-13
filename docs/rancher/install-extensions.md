# Install Rancher extensions

Refer to the [doc](./provisioning-and-import.md) on how to provision Rancher and import the Harvester cluster first.

Edit the `.rancher.extensions` section in `config.yaml`. Each extension can be disabled by setting `enabled` to `false`:

```yaml
rancher:
  extensions:
    harvester-ui:
      enabled: true
      version: "1.8.2"
      git_repo: "https://github.com/harvester/harvester-ui-extension"
      git_branch: "gh-pages"
```

The above config installs the Harvester UI Extension. Usually, you need to modify `version` to match the underlying Harvester cluster and Rancher versions.

Then install the extensions with:

```bash
task op:rancher-install-extensions
```
