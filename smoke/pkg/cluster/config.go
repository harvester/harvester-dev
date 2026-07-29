package cluster

// DeploymentReplicaRule defines how many replicas a deployment should have
type DeploymentReplicaRule struct {
	// Fixed replica count, or 0 if using scaling rule
	Replicas int `yaml:"replicas,omitempty"`
	// Scaling rule: "controller" (scales with controller count), "node" (scales with node count)
	ScaleWith string `yaml:"scaleWith,omitempty"`
	// MinReplicas is the minimum number of replicas (for scaling rules)
	MinReplicas int `yaml:"minReplicas,omitempty"`
	// MaxReplicas is the maximum number of replicas (for scaling rules)
	MaxReplicas int `yaml:"maxReplicas,omitempty"`
}

// ClusterConfig holds configuration for cluster readiness checks
type ClusterConfig struct {
	VIP             string `yaml:"vip,omitempty"`
	NodeCount       int    `yaml:"nodeCount,omitempty"`
	ControllerCount int    `yaml:"controllerCount,omitempty"`
	EtcdCount       int    `yaml:"etcdCount,omitempty"`

	// Expected deployments to verify (format: "namespace/name") - will warn about unexpected ones
	ExpectedDeployments []string `yaml:"expectedDeployments,omitempty"`

	// Deployment replica rules for deployments that scale with cluster size (keyed by "namespace/name")
	DeploymentReplicaRules map[string]DeploymentReplicaRule `yaml:"deploymentReplicaRules,omitempty"`

	// Expected daemonsets to verify (format: "namespace/name") - will warn about unexpected ones
	ExpectedDaemonSets []string `yaml:"expectedDaemonSets,omitempty"`

	// Expected managed charts to verify (format: "namespace/name") - will warn about unexpected ones
	ExpectedManagedCharts []string `yaml:"expectedManagedCharts,omitempty"`

	// Expected KubeVirt resources to verify (format: "namespace/name") - will warn about unexpected ones
	ExpectedKubeVirts []string `yaml:"expectedKubeVirts,omitempty"`
}

// DefaultClusterConfig returns a ClusterConfig with default expected resource names
func DefaultClusterConfig() ClusterConfig {
	return ClusterConfig{
		VIP:             "10.10.0.100",
		NodeCount:       3,
		ControllerCount: 3,
		EtcdCount:       3,
		ExpectedDeployments: []string{
			"cattle-capi-system/capi-controller-manager",
			"harvester-system/cdi-apiserver",
			"harvester-system/cdi-deployment",
			"harvester-system/cdi-operator",
			"harvester-system/cdi-uploadproxy",
			"longhorn-system/csi-attacher",
			"longhorn-system/csi-provisioner",
			"longhorn-system/csi-resizer",
			"longhorn-system/csi-snapshotter",
			"cattle-fleet-local-system/fleet-agent",
			"cattle-fleet-system/fleet-controller",
			"cattle-fleet-system/gitjob",
			"harvester-system/harvester",
			"cattle-system/harvester-cluster-repo",
			"harvester-system/harvester-load-balancer",
			"harvester-system/harvester-load-balancer-webhook",
			"harvester-system/harvester-network-controller-manager",
			"harvester-system/harvester-network-webhook",
			"harvester-system/harvester-node-disk-manager-webhook",
			"harvester-system/harvester-node-manager-webhook",
			"harvester-system/harvester-webhook",
			"cattle-fleet-system/helmops",
			"longhorn-system/longhorn-driver-deployer",
			"longhorn-system/longhorn-ui",
			"cattle-system/rancher",
			"cattle-turtles-system/rancher-turtles-controller-manager",
			"cattle-system/rancher-webhook",
			"kube-system/rke2-coredns-rke2-coredns",
			"kube-system/rke2-coredns-rke2-coredns-autoscaler",
			"kube-system/rke2-metrics-server",
			"kube-system/snapshot-controller",
			"cattle-system/system-upgrade-controller",
			"harvester-system/virt-api",
			"harvester-system/virt-controller",
			"harvester-system/virt-operator",
			"kube-system/whereabouts-controller",
		},
		ExpectedDaemonSets: []string{
			"longhorn-system/engine-image-ei-ff1cedad",
			"harvester-system/harvester-network-controller",
			"harvester-system/harvester-networkfs-manager",
			"harvester-system/harvester-node-disk-manager",
			"harvester-system/harvester-node-manager",
			"kube-system/harvester-whereabouts",
			"harvester-system/kube-vip",
			"longhorn-system/longhorn-csi-plugin",
			"longhorn-system/longhorn-manager",
			"kube-system/rke2-canal",
			"kube-system/rke2-traefik",
			"kube-system/rke2-multus",
			"harvester-system/virt-handler",
		},
		ExpectedManagedCharts: []string{
			"fleet-local/harvester",
			"fleet-local/harvester-crd",
			"fleet-local/kubeovn-operator-crd",
			"fleet-local/rancher-logging-crd",
			"fleet-local/rancher-monitoring-crd",
		},
		ExpectedKubeVirts: []string{
			"harvester-system/kubevirt",
		},
		// Define replica rules for deployments that scale with cluster size
		// Keys are "namespace/name" format
		// - Most deployments have 1 replica (fixed)
		// - Some scale with nodes (3 replicas in 3-node cluster)
		// - Some have 2 replicas for HA
		DeploymentReplicaRules: map[string]DeploymentReplicaRule{
			// Deployments that scale with node count (3 replicas in 3-node cluster)
			"harvester-system/harvester":                      {ScaleWith: "node", MinReplicas: 1, MaxReplicas: 3},
			"harvester-system/harvester-node-manager-webhook": {ScaleWith: "node", MinReplicas: 1, MaxReplicas: 3},
			"harvester-system/harvester-webhook":              {ScaleWith: "node", MinReplicas: 1, MaxReplicas: 3},
			"cattle-system/rancher":                           {ScaleWith: "node", MinReplicas: 1, MaxReplicas: 3},
			// Deployments with 2 replicas for HA
			"harvester-system/harvester-network-controller-manager": {ScaleWith: "node", MinReplicas: 1, MaxReplicas: 2},
			"harvester-system/virt-api":                             {ScaleWith: "node", MinReplicas: 1, MaxReplicas: 2},
			"kube-system/rke2-coredns-rke2-coredns":                 {ScaleWith: "node", MinReplicas: 1, MaxReplicas: 2},
			// Deployments that have fixed replica count
			"harvester-system/virt-controller": {Replicas: 2},
			"longhorn-system/longhorn-ui":      {Replicas: 2},
			"kube-system/snapshot-controller":  {Replicas: 2},
			"longhorn-system/csi-attacher":     {Replicas: 3},
			"longhorn-system/csi-provisioner":  {Replicas: 3},
			"longhorn-system/csi-resizer":      {Replicas: 3},
			"longhorn-system/csi-snapshotter":  {Replicas: 3},
			// All other deployments default to 1 replica
		},
	}
}

// GetExpectedReplicas calculates the expected replica count for a deployment
// deploymentKey should be in "namespace/name" format
func (c *ClusterConfig) GetExpectedReplicas(deploymentKey string) int {
	rule, exists := c.DeploymentReplicaRules[deploymentKey]
	if !exists {
		// Default: 1 replica for deployments not in the rules
		return 1
	}

	// If fixed replicas are specified, use that
	if rule.Replicas > 0 {
		return rule.Replicas
	}

	// Calculate based on scaling rule
	var targetCount int
	switch rule.ScaleWith {
	case "controller":
		targetCount = c.ControllerCount
	case "node":
		targetCount = c.NodeCount
	default:
		return 1
	}

	// Apply min/max bounds
	if rule.MinReplicas > 0 && targetCount < rule.MinReplicas {
		targetCount = rule.MinReplicas
	}
	if rule.MaxReplicas > 0 && targetCount > rule.MaxReplicas {
		targetCount = rule.MaxReplicas
	}

	return targetCount
}
