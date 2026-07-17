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

  private_network_enabled    = local.private_network.enabled
  argocd_internal_fqdn       = local.private_network.argocd_internal_fqdn
  openvpn_server_public_ipv4 = local.private_network.openvpn_server_public_ipv4
  openvpn_server_public_ipv6 = local.private_network.openvpn_server_public_ipv6
  openvpn_tunnel_cidr        = local.private_network.openvpn_tunnel_cidr
  internal_dns_server_ip     = local.private_network.internal_dns_server_ip
  argocd_load_balancer_ipv4  = local.private_network.argocd_load_balancer_ipv4
  argocd_https_port          = local.private_network.argocd_https_port
}
