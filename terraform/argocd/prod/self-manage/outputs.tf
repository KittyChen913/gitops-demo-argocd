output "argocd_self_app_id" {
  description = "Provider resource ID for kustomization_resource.argocd_self_app."
  value       = kustomization_resource.argocd_self_app.id
}

output "argocd_canonical_url" {
  description = "Canonical internal URL managed through argocd-cm."
  value       = local.private_network.enabled ? "https://${local.argocd_internal_fqdn}" : null
}
