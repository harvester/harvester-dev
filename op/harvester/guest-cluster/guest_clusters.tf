
data "rancher2_cluster_v2" "imported-harvester" {
  provider = rancher2.admin
  name = local.config.harvester.name
}

resource "rancher2_cloud_credential" "harvester-dev" {
  provider = rancher2.admin

  name = "harvester-dev"
  harvester_credential_config {
    cluster_id = data.rancher2_cluster_v2.imported-harvester.cluster_v1_id
    cluster_type = "imported"
    kubeconfig_content = data.rancher2_cluster_v2.imported-harvester.kube_config
  }
}

locals {
  # Convert guest_clusters array to map for for_each, filtering enabled clusters only
  guest_clusters_map = {
    for cluster in local.config.guest_clusters : cluster.name => cluster
    if lookup(cluster, "enabled", true) == true
  }
}

# Create a new rancher2 machine config v2 using harvester node_driver
resource "rancher2_machine_config_v2" "harvester-dev-v2" {
  for_each = local.guest_clusters_map
  provider = rancher2.admin
  
  generate_name = "${each.key}-v2"
  harvester_config {
    vm_namespace = each.value.namespace
    cpu_count = "${each.value.cpu}"
    memory_size = "${each.value.memory_in_gib}"
    disk_info = "{\"disks\":[{\"imageName\":\"${each.value.namespace}/${each.value.image_name}\",\"bootOrder\":1,\"size\":${each.value.disk_size}}]}"
    network_info = "{\"interfaces\":[{\"networkName\":\"${each.value.namespace}/${each.value.network}\"}]}"
    ssh_user = "${each.value.ssh_user}"
    user_data = "${each.value.user_data}"
  }
}

data "local_file" "cloud_provider_config" {
  for_each = local.guest_clusters_map
  filename = "${path.module}/../../../state/${each.key}_cloud_provider_kubeconfig.yaml"
}

resource "rancher2_cluster_v2" "guest-clusters" {
  for_each = local.guest_clusters_map
  provider = rancher2.admin

  name = each.key
  kubernetes_version = each.value.kubernetes_version
  rke_config {
    machine_pools {
      name = "pool1"
      cloud_credential_secret_name = rancher2_cloud_credential.harvester-dev.id
      control_plane_role = true
      etcd_role = true
      worker_role = true
      quantity = each.value.node_count
      machine_config {
        kind = rancher2_machine_config_v2.harvester-dev-v2[each.key].kind
        name = rancher2_machine_config_v2.harvester-dev-v2[each.key].name
      }
    }

    # registries {
    #   mirrors {
    #     hostname = "registry.rancher.com"
    #     endpoints = ["http://172.17.0.1:5006"]
    #   }
    # }

    machine_selector_config {
      config = jsonencode(
        {
          cloud-provider-name: "harvester",
          cloud-provider-config: data.local_file.cloud_provider_config[each.key].content
        }
      )
    }
    machine_global_config = <<EOF
cni: "calico"
disable-kube-proxy: false
etcd-expose-metrics: false
EOF
    upgrade_strategy {
      control_plane_concurrency = "1"
      worker_concurrency = "1"
    }
    etcd {
      snapshot_schedule_cron = "0 */5 * * *"
      snapshot_retention = 5
    }

    chart_values = <<EOF
harvester-cloud-provider:
  clusterName: ${each.key}
  cloudConfigPath: /var/lib/rancher/rke2/etc/config-files/cloud-provider-config
EOF
  }
}
