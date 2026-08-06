# ── AWS Provider 設定 ────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region containing the SSM parameters."
  type        = string
  default     = "ap-southeast-1"
}

provider "aws" {
  region = var.aws_region
}

# ── Kustomization Provider（ArgoCD self-managed Application）─────────────────
# 這個 root 不需要 kubernetes provider：self-manage 唯一管理的資源是
# kustomization_resource.argocd_self_app，透過 kbst/kustomization provider
# 連線 Management Cluster 即可，不直接操作原生 Kubernetes API 物件。
provider "kustomization" {
  kubeconfig_raw = local.mgmt_kubeconfig_yaml
}
