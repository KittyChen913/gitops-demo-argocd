output "argocd_namespace" {
  description = "Kubernetes namespace where ArgoCD is installed."
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "mgmt_cluster_endpoint" {
  description = "Management Cluster API endpoint read from SSM."
  value       = data.aws_ssm_parameter.api_endpoint.value
  sensitive   = true
}

output "argocd_worker_cluster_secret_name" {
  description = "Cluster Secret name used by ArgoCD to connect to the Worker Cluster."
  value       = kubernetes_secret_v1.argocd_worker_cluster.metadata[0].name
}
