terraform {
  required_providers {
    rancher2 = {
      source = "rancher/rancher2"
      version = "14.1.1"
    }

    local = {
      source = "hashicorp/local"
    }
  }
}


locals {
  credentials       = yamldecode(file("../../../state/rancher_bootstrap_credentials.yaml"))
  config            = yamldecode(file("../../../config.yaml"))
  harvester_ui_ext  = local.config.rancher.extensions.harvester-ui
  rancher_ai_ui_ext = local.config.rancher.extensions.rancher-ai-ui
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

resource "rancher2_catalog_v2" "harvester" {
  provider = rancher2.admin
  count    = local.harvester_ui_ext.enabled ? 1 : 0

  cluster_id = data.rancher2_cluster.local.id
  name = "harvester"
  git_repo = local.harvester_ui_ext.git_repo
  git_branch = local.harvester_ui_ext.git_branch
}

resource "rancher2_app_v2" "harvester-ui" {
  provider = rancher2.admin
  count    = local.harvester_ui_ext.enabled ? 1 : 0

  cluster_id = data.rancher2_cluster.local.id
  name = "harvester"
  namespace = "cattle-ui-plugin-system"
  repo_name = rancher2_catalog_v2.harvester[0].name
  chart_name = "harvester"
  chart_version = local.harvester_ui_ext.version
}

resource "rancher2_catalog_v2" "rancher-ai-ui" {
  provider = rancher2.admin
  count    = local.rancher_ai_ui_ext.enabled ? 1 : 0

  cluster_id = data.rancher2_cluster.local.id
  name = "rancher-ai-ui"
  git_repo = local.rancher_ai_ui_ext.git_repo
  git_branch = local.rancher_ai_ui_ext.git_branch
}

resource "rancher2_app_v2" "rancher-ai-ui" {
  provider = rancher2.admin
  count    = local.rancher_ai_ui_ext.enabled ? 1 : 0

  cluster_id = data.rancher2_cluster.local.id
  name = "rancher-ai-ui"
  namespace = "cattle-ui-plugin-system"
  repo_name = rancher2_catalog_v2.rancher-ai-ui[0].name
  chart_name = "rancher-ai-ui"
  chart_version = local.rancher_ai_ui_ext.version
}
