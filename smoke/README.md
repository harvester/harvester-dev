# Harvester Smoke Tests

This directory contains focused smoke tests for checking a Harvester cluster after
`harvester-dev` tasks. The code was originally copied from
https://github.com/bk201/harvester-smoke.

These checks are not intended to be a comprehensive end-to-end test suite. For
full Harvester E2E coverage, see https://github.com/harvester/tests.

## Running Tests

### Prerequisites

- Go installed on your system
- Access to a Harvester cluster
- Kubeconfig file for the target cluster. You can also set and export the KUBECONFIG environment variable.
- Configuration files for the smoke test being run

### Cluster Smoke Test

To run the cluster readiness smoke test:

```bash
# copy sample config and edit sane values
cp cluster_config.yaml.sample cluster_config.yaml

go test -v -count 1 -timeout 4h ./pkg/cluster -run TestClusterReady \
    -clusterconfig $(pwd)/cluster_config.yaml \
    -kubeconfig /path/to/your/kubeconfig
```

### Addon Smoke Test

The addon smoke test enables every addon in the configuration, waits for each
addon to report `AddonDeploySuccessful`, and verifies its configured
Deployments, DaemonSets, StatefulSets, and Pods. Addons remain enabled after the
test completes.

```bash
# copy the sample config and customize the addon/resource list if needed
cp addons_config.yaml.sample addons_config.yaml

go test -v -count 1 -timeout 4h ./pkg/addons -run TestAddons \
    -addonsconfig $(pwd)/addons_config.yaml \
    -kubeconfig /path/to/your/kubeconfig
```

The `-addonsconfig` flag is required. Each addon entry contains its namespace,
name, and related resources grouped by Kubernetes resource type. Related
resources are checked even when an addon is already enabled and successfully
deployed.

From the `harvester-dev` repository root, the wrapper can prepare the
configuration and run the test automatically:

```bash
task op:test-addons-ready
```

The wrapper copies `smoke/addons_config.yaml.sample` to
`state/addons_config.yaml`. For clusters with fewer than two nodes, it removes
the descheduler entry before running the test.

### Upgrade Smoke Test

To initialize a Harvester upgrade and wait for it to complete:

```bash
# copy sample config and edit sane values
cp upgrade_config.yaml.sample upgrade_config.yaml

go test -v -count 1 -timeout 4h ./pkg/upgrade -run TestHarvesterUpgrade \
    -upgradeconfig $(pwd)/upgrade_config.yaml \
    -kubeconfig /path/to/your/kubeconfig
```

### Test Parameters

- `-v`: Verbose output
- `-count 1`: Disable test caching
- `-timeout 4h`: Set test timeout to 4 hours
- `-clusterconfig`: Path to cluster configuration file
- `-addonsconfig`: Path to addon configuration file
- `-upgradeconfig`: Path to upgrade configuration file
- `-kubeconfig`: Path to kubeconfig file for cluster access

## Configuration

- `cluster_config.yaml`: Configuration for cluster smoke tests
- `addons_config.yaml`: Addons and related resources for addon smoke tests
- `upgrade_config.yaml`: Configuration for upgrade tests

Refer to the sample configuration files in the repository for the required structure.
