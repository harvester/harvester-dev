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
- Configuration files: `cluster_config.yaml` and `upgrade_config.yaml`

### Cluster Smoke Test

To run the cluster readiness smoke test:

```bash
# copy sample config and edit sane values
cp cluster_config.yaml.sample cluster_config.yaml

go test -v -count 1 -timeout 4h ./pkg/cluster -run TestClusterReady \
    -clusterconfig $(pwd)/cluster_config.yaml \
    -kubeconfig /path/to/your/kubeconfig
```

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
- `-upgradeconfig`: Path to upgrade configuration file
- `-kubeconfig`: Path to kubeconfig file for cluster access

## Configuration

- `cluster_config.yaml`: Configuration for cluster smoke tests
- `upgrade_config.yaml`: Configuration for upgrade tests

Refer to the sample configuration files in the repository for the required structure.
