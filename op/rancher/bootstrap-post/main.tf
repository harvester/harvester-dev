terraform {
  required_providers {
    rancher2 = {
      source = "rancher/rancher2"
      version = "14.1.0"
    }

    local = {
      source = "hashicorp/local"
    }
  }
}


locals {
  credentials = yamldecode(file("../../../state/rancher_bootstrap_credentials.yaml"))
}

provider "rancher2" {
  alias = "admin"

  api_url    = local.credentials.api_url
  token_key = local.credentials.admin_token_key
  insecure = true
}

data "rancher2_cluster" "local" {
  provider = rancher2.admin
  name = "local"
}

output "local_kubeconfig" {
  value = data.rancher2_cluster.local.kube_config
  sensitive = true
}
