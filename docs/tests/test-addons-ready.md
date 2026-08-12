# op:test-addons-ready

The `op:test-addons-ready` task enables the addons listed in
[`smoke/addons_config.yaml.sample`](../../smoke/addons_config.yaml.sample), waits
for them to deploy successfully, and verifies their related Kubernetes
resources.

## Prerequisites

- A running Harvester cluster.
- A kubeconfig at `./kubeconfig` in the repository root.
- `node_count` configured in the root `config.yaml`.

## Configure addons

Each addon entry requires its namespace and name. Related resources are grouped
by type and are identified by their exact namespace and name:

```yaml
addons:
  - namespace: harvester-system
    name: harvester-seeder
    resources:
      deployments:
        - namespace: harvester-system
          name: harvester-seeder
      daemonsets: []
      statefulsets: []
      pods: []
```

The test supports the following related resources:

| Configuration field | Readiness check |
|---------------------|-----------------|
| `deployments` | The desired replicas are updated, ready, and available, and the Deployment has `Available=True`. |
| `daemonsets` | The desired pods are updated, ready, and available. |
| `statefulsets` | The desired replicas are current, updated, ready, and available, and the rollout revisions match. |
| `pods` | The Pod is `Running` and has `Ready=True`. |

Addons without related resources can use empty lists. They are still enabled and
their addon deployment status is checked.

## Run the test

From the repository root, run:

```bash
task op:test-addons-ready
```

The task copies the sample to `state/addons_config.yaml` and passes that file to
the smoke test. When `node_count` is less than `2`, the task removes the
`kube-system/descheduler` entry because descheduler is not expected on a
single-node cluster.

All addons are enabled before polling begins. The test uses a shared five-minute
timeout to wait for addon status `AddonDeploySuccessful`, followed by another
shared five-minute timeout for related resources. If an addon is already enabled
and successfully deployed, the test logs a warning, skips updating it, and still
checks its related resources.

> **Note:** The test leaves addons enabled after it completes.
