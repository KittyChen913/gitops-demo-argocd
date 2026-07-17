output "argocd_namespace" {
  description = "ArgoCD 安裝的 Kubernetes namespace"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "mgmt_cluster_endpoint" {
  description = "Management Cluster API endpoint（來自 SSM）"
  value       = data.aws_ssm_parameter.api_endpoint.value
  sensitive   = true
}
