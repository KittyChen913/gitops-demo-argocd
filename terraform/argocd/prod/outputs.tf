output "argocd_namespace" {
  description = "ArgoCD 安裝的 Kubernetes namespace"
  value       = module.argocd.argocd_namespace
}

output "mgmt_cluster_endpoint" {
  description = "Management Cluster API endpoint（來自 SSM）"
  value       = module.argocd.mgmt_cluster_endpoint
  sensitive   = true
}
