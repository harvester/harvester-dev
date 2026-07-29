package cluster

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"net/http"
	"os"
	"path"
	"testing"
	"time"

	rancherv3 "github.com/rancher/rancher/pkg/apis/management.cattle.io/v3"
	"github.com/sirupsen/logrus"
	"go.yaml.in/yaml/v3"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	kubevirtv1 "kubevirt.io/api/core/v1"
	"sigs.k8s.io/e2e-framework/klient/wait"
	"sigs.k8s.io/e2e-framework/pkg/env"
	"sigs.k8s.io/e2e-framework/pkg/envconf"
	"sigs.k8s.io/e2e-framework/pkg/features"

	"github.com/harvester/harvester-smoke/pkg/version"
)

var (
	testenv           env.Environment
	clusterConfigPath string
	clusterConfig     ClusterConfig
)

func defineClusterTestFlags() error {
	userHome, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	flag.StringVar(&clusterConfigPath, "clusterconfig", path.Join(userHome, "cluster_config.yaml"), "path to the cluster config file (optional, will use defaults if not provided)")

	return nil
}

func loadClusterConfig() error {
	data, err := os.ReadFile(clusterConfigPath)
	if err != nil {
		if os.IsNotExist(err) {
			logrus.Infof("cluster config file not found at %s, using defaults", clusterConfigPath)
			clusterConfig = DefaultClusterConfig()
			return nil
		}
		return err
	}

	err = yaml.Unmarshal(data, &clusterConfig)
	if err != nil {
		return fmt.Errorf("fail to unmarshal cluster config: %v", err)
	}

	// Merge with defaults for any missing lists
	defaults := DefaultClusterConfig()
	if len(clusterConfig.ExpectedDeployments) == 0 {
		clusterConfig.ExpectedDeployments = defaults.ExpectedDeployments
	}
	if len(clusterConfig.ExpectedDaemonSets) == 0 {
		clusterConfig.ExpectedDaemonSets = defaults.ExpectedDaemonSets
	}
	if len(clusterConfig.ExpectedManagedCharts) == 0 {
		clusterConfig.ExpectedManagedCharts = defaults.ExpectedManagedCharts
	}
	if len(clusterConfig.ExpectedKubeVirts) == 0 {
		clusterConfig.ExpectedKubeVirts = defaults.ExpectedKubeVirts
	}
	if clusterConfig.NodeCount == 0 {
		clusterConfig.NodeCount = defaults.NodeCount
	}
	if clusterConfig.ControllerCount == 0 {
		clusterConfig.ControllerCount = defaults.ControllerCount
	}
	if clusterConfig.EtcdCount == 0 {
		clusterConfig.EtcdCount = defaults.EtcdCount
	}
	if clusterConfig.VIP == "" {
		clusterConfig.VIP = defaults.VIP
	}
	if clusterConfig.DeploymentReplicaRules == nil {
		clusterConfig.DeploymentReplicaRules = defaults.DeploymentReplicaRules
	}

	logrus.Infof("cluster config: VIP=%s, NodeCount=%d, ControllerCount=%d, EtcdCount=%d", clusterConfig.VIP,
		clusterConfig.NodeCount, clusterConfig.ControllerCount, clusterConfig.EtcdCount)
	logrus.Infof("Expected deployments: %d, daemonsets: %d, managedcharts: %d, kubevirts: %d",
		len(clusterConfig.ExpectedDeployments), len(clusterConfig.ExpectedDaemonSets), len(clusterConfig.ExpectedManagedCharts), len(clusterConfig.ExpectedKubeVirts))

	return nil
}

func TestMain(m *testing.M) {
	logrus.Infof("harvester-smoke version: %s", version.Version)

	err := defineClusterTestFlags()
	if err != nil {
		fmt.Println("fail to define cluster config flags:", err)
		os.Exit(1)
	}

	// must be called after all custom flags are defined because it calls flag.Parse()
	cfg, err := envconf.NewFromFlags()
	if err != nil {
		fmt.Println("fail to parse flags:", err)
		os.Exit(1)
	}

	err = loadClusterConfig()
	if err != nil {
		fmt.Println("fail to load cluster config:", err)
		os.Exit(1)
	}

	testenv = env.NewWithConfig(cfg)
	r := testenv.EnvConf().Client().Resources()
	err = rancherv3.AddToScheme(r.GetScheme())
	if err != nil {
		fmt.Println("fail to add rancher scheme:", err)
		os.Exit(1)
	}

	err = kubevirtv1.AddToScheme(r.GetScheme())
	if err != nil {
		fmt.Println("fail to add kubevirt scheme:", err)
		os.Exit(1)
	}

	os.Exit(testenv.Run(m))
}

// waitVIPReady checks that the cluster VIP is responding
func waitVIPReady(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	if clusterConfig.VIP == "" {
		t.Log("VIP not configured, skipping VIP check")
		return ctx
	}

	vipURL := fmt.Sprintf("https://%s", clusterConfig.VIP)
	t.Logf("Checking VIP URL: %s", vipURL)

	// Create HTTP client that accepts self-signed certificates
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	client := &http.Client{
		Transport: transport,
		Timeout:   10 * time.Second,
	}

	err := wait.For(func(ctx context.Context) (bool, error) {
		resp, err := client.Get(vipURL)
		if err != nil {
			t.Logf("VIP URL %s not reachable yet: %v", vipURL, err)
			return false, nil
		}
		defer resp.Body.Close() //nolint:errcheck

		if resp.StatusCode == http.StatusOK {
			t.Logf("VIP URL %s is responding with status: %d", vipURL, resp.StatusCode)
			return true, nil
		}

		t.Logf("VIP URL %s returned invalid status: %d", vipURL, resp.StatusCode)
		return false, nil
	}, wait.WithImmediate(), wait.WithInterval(10*time.Second), wait.WithTimeout(30*time.Minute))

	if err != nil {
		t.Fatalf("Failed waiting for VIP URL %s to be ready: %v", vipURL, err)
	}

	return ctx
}

// waitNodesReady checks that all nodes are ready and have correct roles
func waitNodesReady(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	r := cfg.Client().Resources()

	t.Logf("Waiting for %d nodes to be ready (ControllerCount=%d, EtcdCount=%d)",
		clusterConfig.NodeCount, clusterConfig.ControllerCount, clusterConfig.EtcdCount)

	err := wait.For(func(ctx context.Context) (bool, error) {
		var nodeList corev1.NodeList
		err := r.List(ctx, &nodeList)
		if err != nil {
			return false, err
		}

		// Check node count
		if len(nodeList.Items) != clusterConfig.NodeCount {
			t.Logf("Expected %d nodes, found %d", clusterConfig.NodeCount, len(nodeList.Items))
			return false, nil
		}

		controllerCount := 0
		etcdCount := 0
		readyCount := 0

		for _, node := range nodeList.Items {
			// Check if node is ready
			nodeReady := false
			hasMemoryPressure := false
			hasDiskPressure := false
			hasPIDPressure := false

			for _, condition := range node.Status.Conditions {
				switch condition.Type {
				case corev1.NodeReady:
					if condition.Status == corev1.ConditionTrue {
						nodeReady = true
						readyCount++
					}
				case corev1.NodeMemoryPressure:
					if condition.Status == corev1.ConditionTrue {
						hasMemoryPressure = true
					}
				case corev1.NodeDiskPressure:
					if condition.Status == corev1.ConditionTrue {
						hasDiskPressure = true
					}
				case corev1.NodePIDPressure:
					if condition.Status == corev1.ConditionTrue {
						hasPIDPressure = true
					}
				}
			}

			if !nodeReady {
				t.Logf("Node %s is not ready", node.Name)
				return false, nil
			}

			if hasMemoryPressure {
				t.Errorf("Node %s has memory pressure", node.Name)
				return false, fmt.Errorf("node %s has memory pressure", node.Name)
			}

			if hasDiskPressure {
				t.Errorf("Node %s has disk pressure", node.Name)
				return false, fmt.Errorf("node %s has disk pressure", node.Name)
			}

			if hasPIDPressure {
				t.Errorf("Node %s has PID pressure", node.Name)
				return false, fmt.Errorf("node %s has PID pressure", node.Name)
			}

			// Count node roles
			if _, ok := node.Labels["node-role.kubernetes.io/control-plane"]; ok {
				controllerCount++
			}
			if _, ok := node.Labels["node-role.kubernetes.io/etcd"]; ok {
				etcdCount++
			}
		}

		// Verify role counts
		if controllerCount != clusterConfig.ControllerCount {
			t.Logf("Expected %d controller nodes, found %d", clusterConfig.ControllerCount, controllerCount)
			return false, nil
		}

		if etcdCount != clusterConfig.EtcdCount {
			t.Logf("Expected %d etcd nodes, found %d", clusterConfig.EtcdCount, etcdCount)
			return false, nil
		}

		t.Logf("All %d nodes are ready (Controllers=%d, Etcd=%d)",
			readyCount, controllerCount, etcdCount)
		return true, nil
	}, wait.WithImmediate(), wait.WithInterval(30*time.Second), wait.WithTimeout(30*time.Minute))

	if err != nil {
		t.Fatalf("Failed waiting for nodes to be ready: %v", err)
	}

	return ctx
}

// waitDeploymentsReady checks that all deployments are ready
func waitDeploymentsReady(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	r := cfg.Client().Resources()

	t.Logf("Waiting for deployments to be ready (expected: %d)", len(clusterConfig.ExpectedDeployments))

	expectedSet := make(map[string]bool)
	for _, key := range clusterConfig.ExpectedDeployments {
		expectedSet[key] = true
	}

	err := wait.For(func(ctx context.Context) (bool, error) {
		var deploymentList appsv1.DeploymentList
		err := r.List(ctx, &deploymentList)
		if err != nil {
			return false, err
		}

		foundSet := make(map[string]bool)

		for _, deployment := range deploymentList.Items {
			deploymentKey := fmt.Sprintf("%s/%s", deployment.Namespace, deployment.Name)
			foundSet[deploymentKey] = true

			// Skip if this deployment is not in our expected list
			if !expectedSet[deploymentKey] {
				continue
			}

			// For multi-node clusters, validate expected replica count
			if clusterConfig.NodeCount > 1 {
				expectedReplicas := clusterConfig.GetExpectedReplicas(deploymentKey)
				actualReplicas := int(*deployment.Spec.Replicas)

				if actualReplicas != expectedReplicas {
					t.Logf("Deployment %s has %d replicas, expected %d for %d-controller cluster (waiting...)",
						deploymentKey, actualReplicas, expectedReplicas, clusterConfig.ControllerCount)
					return false, nil
				}
			}

			// Check if deployment is ready
			if deployment.Status.ReadyReplicas != *deployment.Spec.Replicas {
				t.Logf("Deployment %s is not ready: %d/%d replicas",
					deploymentKey,
					deployment.Status.ReadyReplicas, *deployment.Spec.Replicas)
				return false, nil
			}

			// Check Available condition
			available := false
			for _, condition := range deployment.Status.Conditions {
				if condition.Type == appsv1.DeploymentAvailable && condition.Status == corev1.ConditionTrue {
					available = true
					break
				}
			}

			if !available {
				t.Logf("Deployment %s is not available", deploymentKey)
				return false, nil
			}
		}

		// Warn about unexpected deployments (log at end to reduce noise)
		for key := range foundSet {
			if !expectedSet[key] {
				t.Logf("WARNING: Unexpected deployment found: %s", key)
			}
		}

		// Check for missing expected deployments
		for key := range expectedSet {
			if !foundSet[key] {
				t.Logf("Expected deployment %s not found", key)
				return false, nil
			}
		}

		t.Logf("All %d expected deployments are ready", len(clusterConfig.ExpectedDeployments))
		return true, nil
	}, wait.WithImmediate(), wait.WithInterval(30*time.Second), wait.WithTimeout(10*time.Minute))

	if err != nil {
		t.Fatalf("Failed waiting for deployments to be ready: %v", err)
	}

	return ctx
}

// waitDaemonSetsReady checks that all daemonsets are ready
func waitDaemonSetsReady(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	r := cfg.Client().Resources()

	t.Logf("Waiting for daemonsets to be ready (expected: %d)", len(clusterConfig.ExpectedDaemonSets))

	expectedSet := make(map[string]bool)
	for _, key := range clusterConfig.ExpectedDaemonSets {
		expectedSet[key] = true
	}

	err := wait.For(func(ctx context.Context) (bool, error) {
		var daemonSetList appsv1.DaemonSetList
		err := r.List(ctx, &daemonSetList)
		if err != nil {
			return false, err
		}

		foundSet := make(map[string]bool)

		for _, daemonSet := range daemonSetList.Items {
			daemonSetKey := fmt.Sprintf("%s/%s", daemonSet.Namespace, daemonSet.Name)
			foundSet[daemonSetKey] = true

			// Skip if this daemonset is not in our expected list
			if !expectedSet[daemonSetKey] {
				continue
			}

			// Check if daemonset is ready
			if daemonSet.Status.NumberReady != daemonSet.Status.DesiredNumberScheduled {
				t.Logf("DaemonSet %s is not ready: %d/%d pods",
					daemonSetKey,
					daemonSet.Status.NumberReady, daemonSet.Status.DesiredNumberScheduled)
				return false, nil
			}

			// Also check numberAvailable
			if daemonSet.Status.NumberAvailable != daemonSet.Status.DesiredNumberScheduled {
				t.Logf("DaemonSet %s is not available: %d/%d pods",
					daemonSetKey,
					daemonSet.Status.NumberAvailable, daemonSet.Status.DesiredNumberScheduled)
				return false, nil
			}
		}

		// Warn about unexpected daemonsets
		for key := range foundSet {
			if !expectedSet[key] {
				t.Logf("WARNING: Unexpected daemonset found: %s", key)
			}
		}

		// Check for missing expected daemonsets
		for key := range expectedSet {
			if !foundSet[key] {
				t.Logf("Expected daemonset %s not found", key)
				return false, nil
			}
		}

		t.Logf("All %d expected daemonsets are ready", len(clusterConfig.ExpectedDaemonSets))
		return true, nil
	}, wait.WithImmediate(), wait.WithInterval(30*time.Second), wait.WithTimeout(10*time.Minute))

	if err != nil {
		t.Fatalf("Failed waiting for daemonsets to be ready: %v", err)
	}

	return ctx
}

// waitManagedChartsReady checks that all managed charts are ready
func waitManagedChartsReady(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	t.Logf("Waiting for managed charts to be ready (expected: %d)", len(clusterConfig.ExpectedManagedCharts))

	expectedSet := make(map[string]bool)
	for _, key := range clusterConfig.ExpectedManagedCharts {
		expectedSet[key] = true
	}

	err := wait.For(func(ctx context.Context) (bool, error) {
		var managedCharts rancherv3.ManagedChartList
		err := cfg.Client().Resources().List(ctx, &managedCharts)
		if err != nil {
			return false, err
		}

		foundSet := make(map[string]bool)

		for _, chart := range managedCharts.Items {
			chartKey := fmt.Sprintf("%s/%s", chart.Namespace, chart.Name)
			foundSet[chartKey] = true

			// Skip if this chart is not in our expected list
			if !expectedSet[chartKey] {
				continue
			}

			ready := rancherv3.Ready.IsTrue(&chart)
			if !ready {
				t.Logf("ManagedChart %s is not ready", chartKey)
				return false, nil
			}
		}

		// Warn about unexpected managed charts
		for key := range foundSet {
			if !expectedSet[key] {
				t.Logf("WARNING: Unexpected managed chart found: %s", key)
			}
		}

		// Check for missing expected charts
		for key := range expectedSet {
			if !foundSet[key] {
				t.Logf("Expected managed chart %s not found", key)
				return false, nil
			}
		}

		t.Logf("All %d expected managed charts are ready", len(clusterConfig.ExpectedManagedCharts))
		return true, nil
	}, wait.WithImmediate(), wait.WithInterval(30*time.Second), wait.WithTimeout(5*time.Minute))

	if err != nil {
		t.Fatalf("Failed waiting for managed charts to be ready: %v", err)
	}

	return ctx
}

// waitKubeVirtsReady checks that all KubeVirt resources are ready
func waitKubeVirtsReady(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	t.Logf("Waiting for KubeVirt resources to be ready (expected: %d)", len(clusterConfig.ExpectedKubeVirts))

	expectedSet := make(map[string]bool)
	for _, key := range clusterConfig.ExpectedKubeVirts {
		expectedSet[key] = true
	}

	err := wait.For(func(ctx context.Context) (bool, error) {
		var kubevirtList kubevirtv1.KubeVirtList
		err := cfg.Client().Resources().List(ctx, &kubevirtList)
		if err != nil {
			return false, err
		}

		foundSet := make(map[string]bool)

		for _, kv := range kubevirtList.Items {
			kvKey := fmt.Sprintf("%s/%s", kv.Namespace, kv.Name)
			foundSet[kvKey] = true

			// Skip if this KubeVirt resource is not in our expected list
			if !expectedSet[kvKey] {
				continue
			}

			// Check phase
			if kv.Status.Phase != kubevirtv1.KubeVirtPhaseDeployed {
				t.Logf("KubeVirt %s is not ready, phase: %s", kvKey, kv.Status.Phase)
				return false, nil
			}

			// Check conditions
			available := false
			progressing := true
			degraded := true

			for _, condition := range kv.Status.Conditions {
				switch condition.Type {
				case kubevirtv1.KubeVirtConditionAvailable:
					if condition.Status == corev1.ConditionTrue {
						available = true
					}
				case kubevirtv1.KubeVirtConditionProgressing:
					if condition.Status == corev1.ConditionFalse {
						progressing = false
					}
				case kubevirtv1.KubeVirtConditionDegraded:
					if condition.Status == corev1.ConditionFalse {
						degraded = false
					}
				}
			}

			if !available {
				t.Logf("KubeVirt %s is not available", kvKey)
				return false, nil
			}
			if progressing {
				t.Logf("KubeVirt %s is still progressing", kvKey)
				return false, nil
			}
			if degraded {
				t.Logf("KubeVirt %s is degraded", kvKey)
				return false, nil
			}
		}

		// Warn about unexpected KubeVirt resources
		for key := range foundSet {
			if !expectedSet[key] {
				t.Logf("WARNING: Unexpected KubeVirt resource found: %s", key)
			}
		}

		// Check for missing expected KubeVirt resources
		for key := range expectedSet {
			if !foundSet[key] {
				t.Logf("Expected KubeVirt resource %s not found", key)
				return false, nil
			}
		}

		t.Logf("All %d expected KubeVirt resources are ready", len(clusterConfig.ExpectedKubeVirts))
		return true, nil
	}, wait.WithImmediate(), wait.WithInterval(30*time.Second), wait.WithTimeout(5*time.Minute))

	if err != nil {
		t.Fatalf("Failed waiting for KubeVirt resources to be ready: %v", err)
	}

	return ctx
}

func TestClusterReady(t *testing.T) {
	f := features.New("cluster-ready").
		WithLabel("type", "cluster-readiness").
		Assess("wait for VIP to be ready", waitVIPReady).
		Assess("wait for nodes to be ready", waitNodesReady).
		Assess("wait for deployments to be ready", waitDeploymentsReady).
		Assess("wait for daemonsets to be ready", waitDaemonSetsReady).
		Assess("wait for managed charts to be ready", waitManagedChartsReady).
		Assess("wait for kubevirt to be ready", waitKubeVirtsReady).
		Feature()

	testenv.Test(t, f)
}
