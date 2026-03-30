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
  config = yamldecode(file("../../../config.yaml"))
}

provider "rancher2" {
  alias = "bootstrap"

  api_url    = "https://${local.config.rancher.hostname}"
  insecure = true
  bootstrap = true
}

resource "rancher2_bootstrap" "admin" {
  provider = rancher2.bootstrap

  initial_password = local.config.rancher.bootstrap_password
  password = local.config.rancher.admin_password
}

# # Provider config for admin
# provider "rancher2" {
#   alias = "admin"

#   api_url = rancher2_bootstrap.admin.url
#   token_key = rancher2_bootstrap.admin.token
#   insecure = true
# }

output "api_url" {
  value = rancher2_bootstrap.admin.url
}

output "admin_token_key" {
  value = rancher2_bootstrap.admin.token
  sensitive = true
}
