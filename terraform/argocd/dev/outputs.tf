output "argocd_namespace" {
  description = "ArgoCD 安裝的 Kubernetes namespace"
  value       = module.argocd.argocd_namespace
}

output "mgmt_cluster_endpoint" {
  description = "Management Cluster API endpoint（來自 SSM）"
  value       = module.argocd.mgmt_cluster_endpoint
  sensitive   = true
}

output "argocd_private_service_name" {
  description = "VPN-only ArgoCD endpoint 使用的 Terraform-owned Kubernetes Service。"
  value       = module.argocd.argocd_private_service_name
}

output "argocd_canonical_url" {
  description = "由 argocd-cm 管理的 canonical internal URL。"
  value       = module.argocd.argocd_canonical_url
}

output "argocd_network_config" {
  description = "internal DNS 與 OpenVPN 設定所需的 values。"
  value       = module.argocd.argocd_network_config
}
