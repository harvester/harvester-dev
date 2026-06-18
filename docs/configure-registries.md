## Configure Registry Mirrors

The `op:harvester-configure-registries` task applies the `containerd-registry` setting to the Harvester cluster, directing containerd to pull images through local mirror endpoints instead of the upstream registries.

### Configuration

Add a `registry_mirrors` list under `.harvester` in `config.yaml`. Each entry requires a `registry` (the upstream registry hostname) and an `endpoint` (the mirror URL):

```yaml
harvester:
  registry_mirrors:
    - registry: docker.io
      endpoint: http://10.8.0.101:5000
    - registry: ghcr.io
      endpoint: http://10.8.0.101:5004
    - registry: k8s.gcr.io
      endpoint: http://10.8.0.101:5001
    - registry: registry.k8s.io
      endpoint: http://10.8.0.101:5005
    - registry: registry.suse.com
      endpoint: http://10.8.0.101:5003
```

### Usage

```sh
task op:harvester-configure-registries
```

This applies a `Setting` resource to the cluster:

```yaml
apiVersion: harvesterhci.io/v1beta1
kind: Setting
metadata:
  name: containerd-registry
value: '{"Mirrors":{"docker.io":{"Endpoints":["http://10.8.0.101:5000"],"Rewrites":null},...},"Configs":null,"Auths":null}'
```

The kubeconfig at `./kubeconfig` is used to reach the cluster. Run `task op:nodes-get-kubeconfig` first if it does not exist yet.
