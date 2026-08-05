output "argocd_namespace" {
  description = "ArgoCD 安裝的 Kubernetes namespace"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "mgmt_cluster_endpoint" {
  description = "Management Cluster API endpoint（來自 SSM）"
  value       = data.aws_ssm_parameter.api_endpoint.value
  sensitive   = true
}

output "argocd_canonical_url" {
  description = "由 argocd-cm 管理的 canonical internal URL。"
  value       = var.private_network_enabled ? "https://${local.argocd_internal_fqdn}" : null
}

# argocd_private_service_name／argocd_network_config 已隨 private-network 資源搬到
# terraform/argocd/<env>/private-network/ 這個獨立 root；輸出見該 root 的 outputs.tf。
