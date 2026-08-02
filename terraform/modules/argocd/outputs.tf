output "argocd_namespace" {
  description = "ArgoCD 安裝的 Kubernetes namespace"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "mgmt_cluster_endpoint" {
  description = "Management Cluster API endpoint（來自 SSM）"
  value       = data.aws_ssm_parameter.api_endpoint.value
  sensitive   = true
}

output "argocd_private_service_name" {
  description = "建立 VPN-only ArgoCD NodeBalancer 的 Terraform-owned Kubernetes Service。"
  value       = try(kubernetes_service_v1.argocd_server_private[0].metadata[0].name, null)
}

output "argocd_canonical_url" {
  description = "由 argocd-cm 管理的 canonical internal URL。"
  value       = var.private_network_enabled ? "https://${local.argocd_internal_fqdn}" : null
}

output "argocd_network_config" {
  description = "Platform Access使用的非機密endpoint hand-off contract。"
  value = {
    enabled                          = var.private_network_enabled
    environment                      = var.deployment_environment
    argocd_internal_fqdn             = local.argocd_internal_fqdn
    argocd_load_balancer_ipv4        = try(linode_networking_ip.argocd_private[0].address, null)
    argocd_https_port                = var.argocd_https_port
    argocd_tls_secret_name           = var.argocd_tls_secret_name
    endpoint_ip_parameter_name       = var.endpoint_ip_parameter_name
    endpoint_hostname_parameter_name = var.endpoint_hostname_parameter_name
  }
}
