locals {
  environment_config = jsondecode(file("${path.module}/../environments/dev.json"))
  private_network    = local.environment_config.private_network
}

module "argocd" {
  source = "../../modules/argocd"

  ssm_path_prefix      = local.environment_config.ssm_path_prefix
  mgmt_cluster_label   = local.environment_config.mgmt_cluster_label
  worker_cluster_label = local.environment_config.worker_cluster_label
  root_applications    = local.environment_config.root_applications

  private_network_enabled             = local.private_network.enabled
  deployment_environment              = local.private_network.environment
  linode_region                       = local.private_network.linode_region
  base_domain_parameter_name          = local.private_network.base_domain_parameter_name
  vpn_public_egress_ip_parameter_name = local.private_network.vpn_public_egress_ip_parameter_name
  endpoint_ip_parameter_name          = local.private_network.endpoint_ip_parameter_name
  endpoint_hostname_parameter_name    = local.private_network.endpoint_hostname_parameter_name
  openvpn_server_public_ipv6          = local.private_network.openvpn_server_public_ipv6
  argocd_https_port                   = local.private_network.argocd_https_port
  argocd_tls_secret_name              = local.private_network.argocd_tls_secret_name
}
