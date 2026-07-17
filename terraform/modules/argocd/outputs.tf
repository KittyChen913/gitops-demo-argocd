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
  description = "建立 VPN-only Argo CD NodeBalancer 的 Terraform-owned Kubernetes Service。"
  value       = try(kubernetes_service_v1.argocd_server_private[0].metadata[0].name, null)
}

output "argocd_canonical_url" {
  description = "由 argocd-cm 管理的 canonical internal URL。"
  value       = var.private_network_enabled ? "https://${var.argocd_internal_fqdn}" : null
}

output "argocd_network_config" {
  description = "設定 internal DNS 與 OpenVPN server 使用的非機密 hand-off values。"
  value = {
    enabled                    = var.private_network_enabled
    argocd_internal_fqdn       = var.argocd_internal_fqdn
    openvpn_server_public_ipv4 = var.openvpn_server_public_ipv4
    openvpn_server_public_ipv6 = var.openvpn_server_public_ipv6
    openvpn_tunnel_cidr        = var.openvpn_tunnel_cidr
    internal_dns_server_ip     = var.internal_dns_server_ip
    argocd_load_balancer_ipv4  = var.argocd_load_balancer_ipv4
    argocd_https_port          = var.argocd_https_port
  }
}
