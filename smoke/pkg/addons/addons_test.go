package addons

import (
	"context"
	"flag"
	"fmt"
	"os"
	"testing"
	"time"

	harvesterv1 "github.com/harvester/harvester/pkg/apis/harvesterhci.io/v1beta1"
	"github.com/sirupsen/logrus"
	"go.yaml.in/yaml/v3"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	k8sresources "sigs.k8s.io/e2e-framework/klient/k8s/resources"
	"sigs.k8s.io/e2e-framework/klient/wait"
	"sigs.k8s.io/e2e-framework/pkg/env"
	"sigs.k8s.io/e2e-framework/pkg/envconf"
	"sigs.k8s.io/e2e-framework/pkg/features"
)

const (
	addonPollInterval = 10 * time.Second
	addonPollTimeout  = 5 * time.Minute
)

type resourceRef struct {
	Namespace string `yaml:"namespace"`
	Name      string `yaml:"name"`
}

type relatedResources struct {
	Deployments  []resourceRef `yaml:"deployments,omitempty"`
	DaemonSets   []resourceRef `yaml:"daemonsets,omitempty"`
	StatefulSets []resourceRef `yaml:"statefulsets,omitempty"`
	Pods         []resourceRef `yaml:"pods,omitempty"`
}

type addonConfig struct {
	Namespace string           `yaml:"namespace"`
	Name      string           `yaml:"name"`
	Resources relatedResources `yaml:"resources,omitempty"`
}

type testConfig struct {
	Addons []addonConfig `yaml:"addons"`
}

var (
	testenv                  env.Environment
	addonConfigPath          string
	addonsConfig             testConfig
	addonsAwaitingDeployment []resourceRef
)

func defineAddonTestFlags() {
	flag.StringVar(&addonConfigPath, "addonsconfig", "", "path to the addon test configuration file")
}

func loadTestConfig() error {
	if addonConfigPath == "" {
		return fmt.Errorf("-addonsconfig is required")
	}

	data, err := os.ReadFile(addonConfigPath)
	if err != nil {
		return fmt.Errorf("failed to read addon config %q: %w", addonConfigPath, err)
	}

	var config testConfig
	if err := yaml.Unmarshal(data, &config); err != nil {
		return fmt.Errorf("failed to unmarshal addon config %q: %w", addonConfigPath, err)
	}
	if err := validateTestConfig(config); err != nil {
		return fmt.Errorf("invalid addon config %q: %w", addonConfigPath, err)
	}

	addonsConfig = config
	logrus.Infof("using addon config from %s", addonConfigPath)
	return nil
}

func validateTestConfig(config testConfig) error {
	if len(config.Addons) == 0 {
		return fmt.Errorf("addons must contain at least one entry")
	}

	for i, addon := range config.Addons {
		if addon.Namespace == "" || addon.Name == "" {
			return fmt.Errorf("addons[%d] must specify namespace and name", i)
		}

		for j, deployment := range addon.Resources.Deployments {
			if deployment.Namespace == "" || deployment.Name == "" {
				return fmt.Errorf("addons[%d].resources.deployments[%d] must specify namespace and name", i, j)
			}
		}
		for j, daemonSet := range addon.Resources.DaemonSets {
			if daemonSet.Namespace == "" || daemonSet.Name == "" {
				return fmt.Errorf("addons[%d].resources.daemonsets[%d] must specify namespace and name", i, j)
			}
		}
		for j, statefulSet := range addon.Resources.StatefulSets {
			if statefulSet.Namespace == "" || statefulSet.Name == "" {
				return fmt.Errorf("addons[%d].resources.statefulsets[%d] must specify namespace and name", i, j)
			}
		}
		for j, pod := range addon.Resources.Pods {
			if pod.Namespace == "" || pod.Name == "" {
				return fmt.Errorf("addons[%d].resources.pods[%d] must specify namespace and name", i, j)
			}
		}
	}

	return nil
}

func TestMain(m *testing.M) {
	logrus.Info("starting Harvester addon smoke test")
	defineAddonTestFlags()

	// This must be called after custom flags are defined because it parses flags.
	cfg, err := envconf.NewFromFlags()
	if err != nil {
		fmt.Println("failed to parse test flags:", err)
		os.Exit(1)
	}

	if err := loadTestConfig(); err != nil {
		fmt.Println("failed to load addon test config:", err)
		os.Exit(1)
	}

	testenv = env.NewWithConfig(cfg)
	resources := testenv.EnvConf().Client().Resources()
	if err := harvesterv1.AddToScheme(resources.GetScheme()); err != nil {
		fmt.Println("failed to register Harvester API types:", err)
		os.Exit(1)
	}

	os.Exit(testenv.Run(m))
}

func enableAddons(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	resources := cfg.Client().Resources()
	addonsAwaitingDeployment = nil

	for _, configuredAddon := range addonsConfig.Addons {
		addon := &harvesterv1.Addon{}
		if err := resources.Get(ctx, configuredAddon.Name, configuredAddon.Namespace, addon); err != nil {
			t.Fatalf("failed to get addon %s/%s: %v", configuredAddon.Namespace, configuredAddon.Name, err)
		}

		ref := resourceRef{Namespace: configuredAddon.Namespace, Name: configuredAddon.Name}
		if addon.Spec.Enabled && addon.Status.Status == harvesterv1.AddonDeployed {
			logrus.Warnf("addon %s/%s is already enabled and deployed; it will not be updated, but its related resources will still be checked", configuredAddon.Namespace, configuredAddon.Name)
			continue
		}

		addonsAwaitingDeployment = append(addonsAwaitingDeployment, ref)
		if addon.Spec.Enabled {
			t.Logf("Addon %s/%s is already enabled with status %q; waiting for deployment", configuredAddon.Namespace, configuredAddon.Name, addon.Status.Status)
			continue
		}

		addon = addon.DeepCopy()
		addon.Spec.Enabled = true
		if err := resources.Update(ctx, addon); err != nil {
			t.Fatalf("failed to enable addon %s/%s: %v", configuredAddon.Namespace, configuredAddon.Name, err)
		}
		t.Logf("Enabled addon %s/%s", configuredAddon.Namespace, configuredAddon.Name)
	}

	return ctx
}

func waitAddonsDeployed(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	if len(addonsAwaitingDeployment) == 0 {
		t.Log("All configured addons were already deployed successfully")
		return ctx
	}

	resources := cfg.Client().Resources()
	err := wait.For(func(ctx context.Context) (bool, error) {
		for _, ref := range addonsAwaitingDeployment {
			addon := &harvesterv1.Addon{}
			if err := resources.Get(ctx, ref.Name, ref.Namespace, addon); err != nil {
				return false, fmt.Errorf("failed to get addon %s/%s: %w", ref.Namespace, ref.Name, err)
			}

			if addon.Status.Status == harvesterv1.AddonDeployed {
				continue
			}
			if harvesterv1.AddonOperationFailed.IsTrue(addon) {
				return false, fmt.Errorf("addon %s/%s deployment failed: status=%q conditions=%v", ref.Namespace, ref.Name, addon.Status.Status, addon.Status.Conditions)
			}

			t.Logf("Addon %s/%s is not deployed yet: status=%q", ref.Namespace, ref.Name, addon.Status.Status)
			return false, nil
		}

		return true, nil
	}, wait.WithImmediate(), wait.WithInterval(addonPollInterval), wait.WithTimeout(addonPollTimeout))
	if err != nil {
		t.Fatalf("failed waiting for addons to deploy: %v", err)
	}

	t.Logf("All %d addons requiring deployment confirmation are ready", len(addonsAwaitingDeployment))
	return ctx
}

func waitRelatedResources(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	resourceCount := 0
	for _, addon := range addonsConfig.Addons {
		resourceCount += len(addon.Resources.Deployments)
		resourceCount += len(addon.Resources.DaemonSets)
		resourceCount += len(addon.Resources.StatefulSets)
		resourceCount += len(addon.Resources.Pods)
	}
	if resourceCount == 0 {
		t.Log("No related addon resources are configured")
		return ctx
	}

	resources := cfg.Client().Resources()
	err := wait.For(func(ctx context.Context) (bool, error) {
		for _, addon := range addonsConfig.Addons {
			t.Logf("Checking related resources for addon %s/%s", addon.Namespace, addon.Name)
			for _, ref := range addon.Resources.Deployments {
				ready, err := deploymentReady(ctx, t, resources, ref)
				if err != nil || !ready {
					return false, err
				}
			}
			for _, ref := range addon.Resources.DaemonSets {
				ready, err := daemonSetReady(ctx, t, resources, ref)
				if err != nil || !ready {
					return false, err
				}
			}
			for _, ref := range addon.Resources.StatefulSets {
				ready, err := statefulSetReady(ctx, t, resources, ref)
				if err != nil || !ready {
					return false, err
				}
			}
			for _, ref := range addon.Resources.Pods {
				ready, err := podReady(ctx, t, resources, ref)
				if err != nil || !ready {
					return false, err
				}
			}
		}

		return true, nil
	}, wait.WithImmediate(), wait.WithInterval(addonPollInterval), wait.WithTimeout(addonPollTimeout))
	if err != nil {
		t.Fatalf("failed waiting for addon resources to become ready: %v", err)
	}

	t.Logf("All %d configured addon resources are ready", resourceCount)
	return ctx
}

func deploymentReady(ctx context.Context, t *testing.T, resources *k8sresources.Resources, ref resourceRef) (bool, error) {
	deployment := &appsv1.Deployment{}
	if err := resources.Get(ctx, ref.Name, ref.Namespace, deployment); err != nil {
		if apierrors.IsNotFound(err) {
			t.Logf("Deployment %s/%s does not exist yet", ref.Namespace, ref.Name)
			return false, nil
		}
		return false, fmt.Errorf("failed to get deployment %s/%s: %w", ref.Namespace, ref.Name, err)
	}

	if deployment.Spec.Replicas == nil || *deployment.Spec.Replicas == 0 {
		t.Logf("Deployment %s/%s does not have a nonzero desired replica count", ref.Namespace, ref.Name)
		return false, nil
	}
	desired := *deployment.Spec.Replicas
	if deployment.Status.ObservedGeneration < deployment.Generation {
		t.Logf("Deployment %s/%s has not observed generation %d", ref.Namespace, ref.Name, deployment.Generation)
		return false, nil
	}
	if deployment.Status.UpdatedReplicas != desired || deployment.Status.ReadyReplicas != desired || deployment.Status.AvailableReplicas != desired {
		t.Logf("Deployment %s/%s is not ready: desired=%d updated=%d ready=%d available=%d", ref.Namespace, ref.Name, desired, deployment.Status.UpdatedReplicas, deployment.Status.ReadyReplicas, deployment.Status.AvailableReplicas)
		return false, nil
	}

	for _, condition := range deployment.Status.Conditions {
		if condition.Type == appsv1.DeploymentAvailable && condition.Status == corev1.ConditionTrue {
			return true, nil
		}
	}

	t.Logf("Deployment %s/%s does not have Available=True", ref.Namespace, ref.Name)
	return false, nil
}

func daemonSetReady(ctx context.Context, t *testing.T, resources *k8sresources.Resources, ref resourceRef) (bool, error) {
	daemonSet := &appsv1.DaemonSet{}
	if err := resources.Get(ctx, ref.Name, ref.Namespace, daemonSet); err != nil {
		if apierrors.IsNotFound(err) {
			t.Logf("DaemonSet %s/%s does not exist yet", ref.Namespace, ref.Name)
			return false, nil
		}
		return false, fmt.Errorf("failed to get daemonset %s/%s: %w", ref.Namespace, ref.Name, err)
	}

	desired := daemonSet.Status.DesiredNumberScheduled
	if daemonSet.Status.ObservedGeneration < daemonSet.Generation {
		t.Logf("DaemonSet %s/%s has not observed generation %d", ref.Namespace, ref.Name, daemonSet.Generation)
		return false, nil
	}
	if daemonSet.Status.UpdatedNumberScheduled != desired || daemonSet.Status.NumberReady != desired || daemonSet.Status.NumberAvailable != desired {
		t.Logf("DaemonSet %s/%s is not ready: desired=%d updated=%d ready=%d available=%d", ref.Namespace, ref.Name, desired, daemonSet.Status.UpdatedNumberScheduled, daemonSet.Status.NumberReady, daemonSet.Status.NumberAvailable)
		return false, nil
	}

	return true, nil
}

func statefulSetReady(ctx context.Context, t *testing.T, resources *k8sresources.Resources, ref resourceRef) (bool, error) {
	statefulSet := &appsv1.StatefulSet{}
	if err := resources.Get(ctx, ref.Name, ref.Namespace, statefulSet); err != nil {
		if apierrors.IsNotFound(err) {
			t.Logf("StatefulSet %s/%s does not exist yet", ref.Namespace, ref.Name)
			return false, nil
		}
		return false, fmt.Errorf("failed to get statefulset %s/%s: %w", ref.Namespace, ref.Name, err)
	}

	if statefulSet.Spec.Replicas == nil || *statefulSet.Spec.Replicas == 0 {
		t.Logf("StatefulSet %s/%s does not have a nonzero desired replica count", ref.Namespace, ref.Name)
		return false, nil
	}
	desired := *statefulSet.Spec.Replicas
	if statefulSet.Status.ObservedGeneration < statefulSet.Generation {
		t.Logf("StatefulSet %s/%s has not observed generation %d", ref.Namespace, ref.Name, statefulSet.Generation)
		return false, nil
	}
	if statefulSet.Status.Replicas != desired || statefulSet.Status.CurrentReplicas != desired || statefulSet.Status.UpdatedReplicas != desired || statefulSet.Status.ReadyReplicas != desired || statefulSet.Status.AvailableReplicas != desired {
		t.Logf("StatefulSet %s/%s is not ready: desired=%d current=%d updated=%d ready=%d available=%d", ref.Namespace, ref.Name, desired, statefulSet.Status.CurrentReplicas, statefulSet.Status.UpdatedReplicas, statefulSet.Status.ReadyReplicas, statefulSet.Status.AvailableReplicas)
		return false, nil
	}
	if statefulSet.Status.CurrentRevision != statefulSet.Status.UpdateRevision {
		t.Logf("StatefulSet %s/%s rollout is incomplete: currentRevision=%q updateRevision=%q", ref.Namespace, ref.Name, statefulSet.Status.CurrentRevision, statefulSet.Status.UpdateRevision)
		return false, nil
	}

	return true, nil
}

func podReady(ctx context.Context, t *testing.T, resources *k8sresources.Resources, ref resourceRef) (bool, error) {
	pod := &corev1.Pod{}
	if err := resources.Get(ctx, ref.Name, ref.Namespace, pod); err != nil {
		if apierrors.IsNotFound(err) {
			t.Logf("Pod %s/%s does not exist yet", ref.Namespace, ref.Name)
			return false, nil
		}
		return false, fmt.Errorf("failed to get pod %s/%s: %w", ref.Namespace, ref.Name, err)
	}

	if pod.Status.Phase != corev1.PodRunning {
		t.Logf("Pod %s/%s is not running: phase=%s", ref.Namespace, ref.Name, pod.Status.Phase)
		return false, nil
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodReady && condition.Status == corev1.ConditionTrue {
			return true, nil
		}
	}

	t.Logf("Pod %s/%s does not have Ready=True", ref.Namespace, ref.Name)
	return false, nil
}

func TestAddons(t *testing.T) {
	feature := features.New("addons").
		WithLabel("type", "addon-readiness").
		Assess("enable addons", enableAddons).
		Assess("wait for addons to deploy", waitAddonsDeployed).
		Assess("wait for addon resources to be ready", waitRelatedResources).
		Feature()

	testenv.Test(t, feature)
}
