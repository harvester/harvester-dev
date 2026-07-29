package upgrade

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path"
	"testing"
	"time"

	harvv1api "github.com/harvester/harvester/pkg/apis/harvesterhci.io/v1beta1"
	rancherv3 "github.com/rancher/rancher/pkg/apis/management.cattle.io/v3"
	"github.com/rancher/wrangler/v3/pkg/condition"
	"github.com/sirupsen/logrus"
	"go.yaml.in/yaml/v3"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/e2e-framework/klient/k8s"
	"sigs.k8s.io/e2e-framework/klient/wait"
	"sigs.k8s.io/e2e-framework/klient/wait/conditions"
	"sigs.k8s.io/e2e-framework/pkg/env"
	"sigs.k8s.io/e2e-framework/pkg/envconf"
	"sigs.k8s.io/e2e-framework/pkg/features"
)

const (
	harvesterSystemNamespace = "harvester-system"
	managedChartNamespace    = "fleet-local"
	upgradeVersion           = "v8.8.8"

	skipVersionCheckAnnotation = "harvesterhci.io/skip-version-check"
)

var (
	testenv           env.Environment
	upgradeConfigPath string
	upgradeConfig     TestConfig

	upgradeName string
)

func defineUpgradeTestFlags() error {
	userHome, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	flag.StringVar(&upgradeConfigPath, "upgradeconfig", path.Join(userHome, "upgrade_config.yaml"), "path to the upgrade config file")

	return nil
}

type TestConfig struct {
	NodeCount        int    `yaml:"nodeCount,omitempty"`
	UpgradeISOURL    string `yaml:"upgradeISOURL,omitempty"`
	SkipVersionCheck bool   `yaml:"skipVersionCheck,omitempty"`
}

func loadTestConfig() error {

	logrus.Infof("using test config path: %s", upgradeConfigPath)
	data, err := os.ReadFile(upgradeConfigPath)
	if err != nil {
		return err
	}

	err = yaml.Unmarshal(data, &upgradeConfig)
	if err != nil {
		return fmt.Errorf("fail to unmarshal answer file: %v", err)
	}
	logrus.Infof("test config: %+v", upgradeConfig)

	return nil
}

func TestMain(m *testing.M) {
	err := defineUpgradeTestFlags()
	if err != nil {
		fmt.Println("fail to define test flags:", err)
		os.Exit(1)
	}

	// must be called after all custom flags are defined because it calls flag.Parse()
	cfg, err := envconf.NewFromFlags()
	if err != nil {
		fmt.Println("fail to parse flags:", err)
		os.Exit(1)
	}

	err = loadTestConfig()
	if err != nil {
		fmt.Println("fail to load test config:", err)
		os.Exit(1)
	}

	testenv = env.NewWithConfig(cfg)
	if err != nil {
		fmt.Println("fail to create test env:", err)
		os.Exit(1)
	}

	r := testenv.EnvConf().Client().Resources()
	err = harvv1api.AddToScheme(r.GetScheme())
	if err != nil {
		fmt.Println("fail to add to scheme:", err)
		os.Exit(1)
	}

	err = rancherv3.AddToScheme(r.GetScheme())
	if err != nil {
		fmt.Println("fail to add to scheme:", err)
		os.Exit(1)
	}
	os.Exit(testenv.Run(m))
}

func createVersion(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	r := cfg.Client().Resources()

	existing := &harvv1api.Version{}
	err := r.Get(ctx, upgradeVersion, harvesterSystemNamespace, existing)
	if err == nil {
		t.Logf("version %s already exists, deleting it first", upgradeVersion)
		if err := r.Delete(ctx, existing); err != nil {
			t.Fatalf("fail to delete existing version: %v", err)
		}
	} else if !apierrors.IsNotFound(err) {
		t.Fatalf("fail to check existing version: %v", err)
	}

	version := &harvv1api.Version{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: harvesterSystemNamespace,
			Name:      upgradeVersion,
		},
		Spec: harvv1api.VersionSpec{
			ISOURL: upgradeConfig.UpgradeISOURL,
		},
	}

	if err := r.Create(ctx, version); err != nil {
		t.Fatalf("fail to create version: %v", err)
	}

	return ctx
}

func createUpgrade(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	r := cfg.Client().Resources()

	upgrade := &harvv1api.Upgrade{
		ObjectMeta: metav1.ObjectMeta{
			GenerateName: "hvst-upgrade-",
			Namespace:    harvesterSystemNamespace,
			Annotations: map[string]string{
				skipVersionCheckAnnotation: fmt.Sprintf("%v", upgradeConfig.SkipVersionCheck),
			},
		},
		Spec: harvv1api.UpgradeSpec{
			Version:    upgradeVersion,
			LogEnabled: true,
		},
	}
	err := r.Create(ctx, upgrade)
	if err != nil {
		t.Fatal(err)
	}

	t.Logf("upgrade is created: %s", upgrade.Name)

	upgradeName = upgrade.Name

	return ctx
}

func wait_upgrade_condition(ctx context.Context, t *testing.T, cfg *envconf.Config, interval, timeout time.Duration, cond condition.Cond) context.Context {
	r := cfg.Client().Resources()

	var upgrade harvv1api.Upgrade
	err := r.Get(ctx, upgradeName, harvesterSystemNamespace, &upgrade)
	if err != nil {
		t.Fatalf("fail to get upgrade: %v", err)
	}

	t.Logf("wait for upgrade status condition: %s, interval: %s, timeout: %s", cond, interval, timeout)
	err = wait.For(conditions.New(cfg.Client().Resources(harvesterSystemNamespace)).ResourceMatch(
		&upgrade,
		func(object k8s.Object) bool {
			u := object.(*harvv1api.Upgrade)

			if harvv1api.UpgradeCompleted.IsFalse(u) {
				t.Fatalf("upgrade failed: %v", u.Status)
			}
			return cond.IsTrue(u)
		},
	), wait.WithImmediate(), wait.WithInterval(interval), wait.WithTimeout(timeout))

	if err != nil {
		t.Fatalf("Error on waiting upgrade status condition: %s, error: %v", cond, err)
	}
	return ctx
}

func wait_image(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	return wait_upgrade_condition(ctx, t, cfg, 10*time.Second, 10*time.Minute, harvv1api.ImageReady)
}

func wait_log(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	return wait_upgrade_condition(ctx, t, cfg, 10*time.Second, 5*time.Minute, harvv1api.LogReady)
}

func wait_repo(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	return wait_upgrade_condition(ctx, t, cfg, 10*time.Second, 5*time.Minute, harvv1api.RepoProvisioned)
}

func wait_node_prepared(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	totalWaitTime := time.Duration(upgradeConfig.NodeCount) * 12 * time.Minute
	// We usually need 10 minutes on lab machines (VMs)
	return wait_upgrade_condition(ctx, t, cfg, 30*time.Second, totalWaitTime, harvv1api.NodesPrepared)
}

func wait_system_service_upgraded(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	return wait_upgrade_condition(ctx, t, cfg, 30*time.Second, 30*time.Minute, harvv1api.SystemServicesUpgraded)
}

func wait_nodes_upgraded(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	return wait_upgrade_condition(ctx, t, cfg, 30*time.Second, 45*time.Minute, harvv1api.NodesUpgraded)
}

func wait_upgraded_complete(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	return wait_upgrade_condition(ctx, t, cfg, 10*time.Second, 3*time.Minute, harvv1api.UpgradeCompleted)
}

func wait_managed_charts(ctx context.Context, t *testing.T, cfg *envconf.Config) context.Context {
	var managedCharts rancherv3.ManagedChartList
	err := cfg.Client().Resources(managedChartNamespace).List(ctx, &managedCharts)
	if err != nil {
		t.Fatal(err)
	}

	// wait until all managed charts are ready
	err = wait.For(conditions.New(cfg.Client().Resources(managedChartNamespace)).ResourceListMatchN(
		&managedCharts,
		len(managedCharts.Items),
		func(object k8s.Object) bool {
			m := object.(*rancherv3.ManagedChart)
			ready := rancherv3.Ready.IsTrue(m)
			if !ready {
				t.Logf("managed chart: %s is not ready", m.Name)
			}
			return ready
		},
	), wait.WithImmediate(), wait.WithInterval(10*time.Second), wait.WithTimeout(5*time.Minute))

	if err != nil {
		t.Fatal(err)
	}
	return ctx
}

func TestHarvesterUpgrade(t *testing.T) {
	f1 := features.New("upgrade").
		WithLabel("type", "upgrade").
		Assess("wait managed charts", wait_managed_charts).
		Assess("create a version", createVersion).
		Assess("create an upgrade", createUpgrade).
		Assess("wait log", wait_log).
		Assess("wait image", wait_image).
		Assess("wait repo", wait_repo).
		Assess("wait node prepared", wait_node_prepared).
		Assess("wait system services upgraded", wait_system_service_upgraded).
		Assess("wait nodes upgraded", wait_nodes_upgraded).
		Assess("wait upgrade complete", wait_upgraded_complete).
		Feature()

	testenv.Test(t, f1)
}
