output "argocd_root_app_ids" {
  description = "Provider resource IDs for kustomization_resource.argocd_root_app by team."
  value       = { for key, app in kustomization_resource.argocd_root_app : key => app.id }
}
