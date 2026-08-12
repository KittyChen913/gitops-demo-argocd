output "argocd_private_service_name" {
  description = "Terraform-owned Kubernetes Service that creates the VPN-only ArgoCD NodeBalancer."
  value       = kubernetes_service_v1.argocd_server_private.metadata[0].name
}

output "argocd_network_config" {
  description = "Non-sensitive endpoint hand-off contract consumed by OpenVPN/DNS."
  value = {
    enabled                          = local.private_network.enabled
    environment                      = local.private_network.environment
    argocd_internal_fqdn             = local.argocd_internal_fqdn
    argocd_load_balancer_ipv4        = linode_networking_ip.argocd_private.address
    argocd_https_port                = local.private_network.argocd_https_port
    argocd_tls_secret_name           = local.private_network.argocd_tls_secret_name
    endpoint_ip_parameter_name       = local.private_network.endpoint_ip_parameter_name
    endpoint_hostname_parameter_name = local.private_network.endpoint_hostname_parameter_name
  }
}
