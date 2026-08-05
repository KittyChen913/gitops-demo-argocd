locals {
  environment_config = jsondecode(file("${path.module}/../environments/prod.json"))
  private_network    = local.environment_config.private_network
}

module "argocd" {
  source = "../../modules/argocd"

  ssm_path_prefix      = local.environment_config.ssm_path_prefix
  mgmt_cluster_label   = local.environment_config.mgmt_cluster_label
  worker_cluster_label = local.environment_config.worker_cluster_label
  root_applications    = local.environment_config.root_applications

  private_network_enabled        = local.private_network.enabled
  deployment_environment         = local.private_network.environment
  internal_domain_parameter_name = local.private_network.internal_domain_parameter_name
}
