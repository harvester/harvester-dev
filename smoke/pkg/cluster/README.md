# Cluster Readiness Test

This package contains a focused smoke test for checking that a Harvester cluster is ready and operational.

## Test Overview

The `TestClusterReady` test validates cluster health by checking resources in the following order:

0. **VIP**: Verifies the cluster VIP is responding to HTTPS requests (accepts self-signed certificates)
1. **Nodes**: Verifies all nodes are Ready, have correct roles, and no pressure conditions
2. **Deployments**: Ensures all expected deployments have desired replicas available
3. **DaemonSets**: Confirms all expected daemonsets have all pods ready
4. **ManagedCharts**: Validates all expected managed charts are in Ready state
5. **KubeVirt**: Checks KubeVirt resources are in Deployed phase with Available condition

## Configuration

The test uses a configuration file (`cluster_config.yaml`) to specify expected resources. If the config file is not found, it uses built-in defaults.

### Config File Location

By default, the test looks for `cluster_config.yaml` in your home directory. You can override this with the `-clusterconfig` flag:

```bash
go test -v ./pkg/cluster -clusterconfig=/path/to/cluster_config.yaml
```

### Configuration Options

```yaml
# VIP address of the cluster
vip: 10.10.0.100

# Total number of nodes expected in the cluster
nodeCount: 3

# Number of nodes with control-plane role
controllerCount: 3

# Number of nodes with etcd role
etcdCount: 3

# List of expected deployments (format: "namespace/name")
expectedDeployments:
  - harvester-system/harvester
  - cattle-system/rancher
  - longhorn-system/csi-attacher
  # ... more deployments

# List of expected daemonsets (format: "namespace/name")
expectedDaemonSets:
  - harvester-system/harvester-network-controller
  - longhorn-system/longhorn-manager
  - kube-system/rke2-canal
  # ... more daemonsets

# List of expected managed charts (format: "namespace/name")
expectedManagedCharts:
  - fleet-local/harvester
  - fleet-local/harvester-crd
  # ... more charts

# List of expected KubeVirt resources (format: "namespace/name")
expectedKubeVirts:
  - harvester-system/kubevirt

# Deployment replica rules (optional, defaults provided)
# Defines expected replicas for deployments that scale with cluster size
# Keys must be in "namespace/name" format
deploymentReplicaRules:
  harvester-system/harvester:
    scaleWith: "node"  # Scales with node count
    minReplicas: 1
    maxReplicas: 3
  cattle-system/rancher:
    scaleWith: "node"
    minReplicas: 1
    maxReplicas: 3
  harvester-system/virt-api:
    scaleWith: "node"
    minReplicas: 1
    maxReplicas: 2
  # ... more rules (most deployments default to 1 replica)
```

## Running the Test

### Basic Usage

```bash
# Run with default config
export KUBECONFIG=/path/to/kubeconfig
go test -count 1 -timeout 4h -v ./pkg/cluster -run TestClusterReady

# Run with custom config file
export KUBECONFIG=/path/to/kubeconfig
go test -count 1 -timeout 4h -v ./pkg/cluster -run TestClusterReady -clusterconfig=/path/to/cluster_config.yaml

# Run with kubeconfig
go test -count 1 -timeout 4h -v ./pkg/cluster -run TestClusterReady -clusterconfig=/path/to/cluster_config.yaml -kubeconfig=$HOME/.kube/config
```

### Test Behavior

- **VIP Validation**:
  - Checks that the cluster VIP responds to HTTPS requests
  - Accepts self-signed certificates (uses insecure TLS skip verify)
  - Accepts OK HTTP status code 200
  - Skips check if VIP is not configured
  
- **Node Validation**: 
  - Checks that the exact number of nodes are present and Ready
  - Verifies controller and etcd role counts match expectations
  - Fails if any node has MemoryPressure, DiskPressure, or PIDPressure
  
- **Resource Validation**:
  - Verifies all expected deployments/daemonsets/charts are present and ready
  - Uses **namespace/name** format for deployment keys to avoid ambiguity
  - Logs warnings for unexpected resources (doesn't fail the test)
  - Fails fast on the first unhealthy expected resource
  - **For multi-node clusters (nodeCount > 1)**: Validates deployment replica counts
    - Checks if deployments have expected replicas based on cluster size
    - Some deployments scale with node count (e.g., harvester, rancher, csi-*)
    - **Blocks and keeps polling until replica count matches expectations**


## Customizing for Different Clusters

You can create different config files for different cluster configurations:

```bash
# Single-node cluster
go test -v ./pkg/cluster -clusterconfig=./configs/single-node.yaml

# Production cluster
go test -v ./pkg/cluster -clusterconfig=./configs/production.yaml
```

Example single-node config:
```yaml
vip: 10.10.0.100
nodeCount: 1
controllerCount: 1
etcdCount: 1
```

## Interpreting Results

### Success Output
```
time="2026-03-15T21:38:26+08:00" level=info msg="cluster config: VIP=10.10.0.100, NodeCount=2, ControllerCount=1, EtcdCount=1"
time="2026-03-15T21:38:26+08:00" level=info msg="Expected deployments: 36, daemonsets: 13, managedcharts: 5, kubevirts: 1"
=== RUN   TestClusterReady
=== RUN   TestClusterReady/cluster-ready
=== RUN   TestClusterReady/cluster-ready/wait_for_VIP_to_be_ready
    cluster_test.go:136: Checking VIP URL: https://10.10.0.100
    cluster_test.go:157: VIP URL https://10.10.0.100 is responding with status: 200
=== RUN   TestClusterReady/cluster-ready/wait_for_deployments_to_be_ready
    cluster_test.go:281: Waiting for deployments to be ready (expected: 36)
    cluster_test.go:367: All 36 expected deployments are ready
=== RUN   TestClusterReady/cluster-ready/wait_for_daemonsets_to_be_ready
    cluster_test.go:382: Waiting for daemonsets to be ready (expected: 13)
    cluster_test.go:450: All 13 expected daemonsets are ready
=== RUN   TestClusterReady/cluster-ready/wait_for_managed_charts_to_be_ready
    cluster_test.go:463: Waiting for managed charts to be ready (expected: 5)
    cluster_test.go:492: ManagedChart fleet-local/harvester is not ready
    cluster_test.go:492: ManagedChart fleet-local/harvester is not ready
    cluster_test.go:492: ManagedChart fleet-local/harvester is not ready
    cluster_test.go:492: ManagedChart fleet-local/harvester is not ready
    cluster_test.go:517: All 5 expected managed charts are ready
=== RUN   TestClusterReady/cluster-ready/wait_for_kubevirt_to_be_ready
    cluster_test.go:530: Waiting for KubeVirt resources to be ready (expected: 1)
    cluster_test.go:619: All 1 expected KubeVirt resources are ready
--- PASS: TestClusterReady (120.45s)
    --- PASS: TestClusterReady/cluster-ready (120.45s)
        --- PASS: TestClusterReady/cluster-ready/wait_for_VIP_to_be_ready (0.39s)
        --- PASS: TestClusterReady/cluster-ready/wait_for_deployments_to_be_ready (0.01s)
        --- PASS: TestClusterReady/cluster-ready/wait_for_daemonsets_to_be_ready (0.01s)
        --- PASS: TestClusterReady/cluster-ready/wait_for_managed_charts_to_be_ready (120.04s)
        --- PASS: TestClusterReady/cluster-ready/wait_for_kubevirt_to_be_ready (0.01s)
PASS
ok  	github.com/bk201/harv-tests/pkg/cluster	120.463s
```

### Failure Examples

**Node not ready:**
```
cluster_test.go:152: Node node2 is not ready
cluster_test.go:181: Failed waiting for nodes to be ready: timeout
```

**Deployment not ready:**
```
cluster_test.go:213: Deployment harvester-system/harvester is not ready: 0/1 replicas
cluster_test.go:246: Failed waiting for deployments to be ready: timeout
```

**Unexpected resource warning:**
```
cluster_test.go:229: WARNING: Unexpected deployment found: custom-app
```

## Deployment Replica Validation

For multi-node clusters, the test validates that deployments have the expected number of replicas based on cluster size. This is important because some deployments scale with the number of nodes for high availability.

**The test will block and keep polling until the replica count matches expectations.**

### Built-in Scaling Rules

The following deployments scale with node count (up to specified max):

**3 replicas max** (one per node):
- longhorn-system/csi-attacher, longhorn-system/csi-provisioner, longhorn-system/csi-resizer, longhorn-system/csi-snapshotter
- harvester-system/harvester, harvester-system/harvester-node-manager-webhook, harvester-system/harvester-webhook
- cattle-system/rancher

**2 replicas max** (for HA):
- harvester-system/harvester-network-controller-manager
- longhorn-system/longhorn-ui
- kube-system/rke2-coredns-rke2-coredns
- kube-system/snapshot-controller
- harvester-system/virt-api, harvester-system/virt-controller

**All other deployments**: 1 replica (fixed)

### Custom Replica Rules

You can customize replica expectations in your `cluster_config.yaml`. **Keys must use "namespace/name" format:**

```yaml
deploymentReplicaRules:
  my-namespace/my-custom-deployment:
    scaleWith: "node"  # or "controller" if you want to scale with controller count
    minReplicas: 1
    maxReplicas: 3
  my-namespace/my-fixed-deployment:
    replicas: 2  # Fixed replica count
```

### Validation Behavior

- Checks only happen when `nodeCount > 1`
- **Blocks and keeps polling until replicas match expected count**
- Uses 30-second intervals with 10-minute timeout
- This ensures deployments have scaled appropriately before proceeding

## Troubleshooting

1. **Test times out**: Resources may be stuck or cluster is still starting. Check pod logs and events.

2. **Unexpected resources warning**: Your cluster has additional resources not in the expected list. Update `cluster_config.yaml` if this is expected.

3. **Missing expected resources**: 
   - Resource may be named differently (check actual names with `kubectl get <resource>`)
   - Resource deployment may have failed (check events)
   - Config file may have outdated names

4. **Node role mismatch**: Verify your cluster topology matches the config. Some clusters may have dedicated etcd nodes vs combined control-plane+etcd nodes.

## Development

To add new checks:

1. Add a new `wait<ResourceType>Ready` function following the existing pattern
2. Add the new check to the `TestClusterReady` feature chain
3. Update config structure if new configuration options are needed
4. Update this README with documentation

### Code Structure

- `config.go`: Configuration structures and defaults
- `cluster_test.go`: Test implementation and wait functions
- `README.md`: This documentation
