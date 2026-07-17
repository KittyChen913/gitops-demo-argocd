# ── AWS Provider 設定 ────────────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region
}

# ── Kubernetes Provider（Management Cluster）────────────────────────────────
# 連線資訊由 AWS SSM Parameter Store 取得（見 main.tf 的 data sources）。
# 用於建立 Worker Cluster Secret。
provider "kubernetes" {
  host                   = data.aws_ssm_parameter.api_endpoint.value
  cluster_ca_certificate = base64decode(data.aws_ssm_parameter.ca_cert.value)
  token                  = data.aws_ssm_parameter.token.value
}

# ── Kustomization Provider（ArgoCD 安裝）──────────────────────────────────────
# 沿用 SSM 連線資訊，透過 kubeconfig_raw 連線至 Management Cluster，
# 套用 argocd/install/ 目錄的 Kustomize manifest。
provider "kustomization" {
  kubeconfig_raw = local.mgmt_kubeconfig_yaml
}
