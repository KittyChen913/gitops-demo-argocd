# ── AWS Provider 設定 ────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region containing the SSM parameters."
  type        = string
  default     = "ap-southeast-1"
}

provider "aws" {
  region = var.aws_region
}

# ── Kubernetes Provider 設定（Management Cluster）───────────────────────────
# 連線資訊由 AWS SSM Parameter Store 取得（見 main.tf 的 data sources）。
# 用於建立 argocd-server-private companion Service。
provider "kubernetes" {
  host                   = data.aws_ssm_parameter.api_endpoint.value
  cluster_ca_certificate = base64decode(data.aws_ssm_parameter.ca_cert.value)
  token                  = data.aws_ssm_parameter.token.value
}

# ── Linode Provider 設定 ─────────────────────────────────────────────────────
# 沿用既有 LINODE_TOKEN 環境變數注入模式（見 .github/workflows/_terraform-apply-stage.yml
# 的「Load Linode provider material」step），這裡不需要額外的 provider 區塊。
