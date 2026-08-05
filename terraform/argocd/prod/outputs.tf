output "argocd_namespace" {
  description = "ArgoCD 安裝的 Kubernetes namespace"
  value       = module.argocd.argocd_namespace
}

output "mgmt_cluster_endpoint" {
  description = "Management Cluster API endpoint（來自 SSM）"
  value       = module.argocd.mgmt_cluster_endpoint
  sensitive   = true
}

output "argocd_canonical_url" {
  description = "由 argocd-cm 管理的 canonical internal URL。"
  value       = module.argocd.argocd_canonical_url
}

# argocd_private_service_name／argocd_network_config 已隨 private-network 資源搬到
# terraform/argocd/prod/private-network/ 這個獨立 root；輸出見該 root 的 outputs.tf。
