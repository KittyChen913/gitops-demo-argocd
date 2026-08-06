locals {
  environment_config = jsondecode(file("${path.module}/../../environments/dev.json"))
  manifest_root      = abspath("${path.module}/../../../../argocd")
}

# ── SSM Parameter Store：lke-dev-mgmt 連線資訊（供 kustomization provider 使用）──
data "aws_ssm_parameter" "api_endpoint" {
  name = "${local.environment_config.ssm_path_prefix}/${local.environment_config.mgmt_cluster_label}/api-endpoint"
}

data "aws_ssm_parameter" "ca_cert" {
  name = "${local.environment_config.ssm_path_prefix}/${local.environment_config.mgmt_cluster_label}/ca-cert"
}

data "aws_ssm_parameter" "token" {
  name            = "${local.environment_config.ssm_path_prefix}/${local.environment_config.mgmt_cluster_label}/token"
  with_decryption = true
}

locals {
  mgmt_kubeconfig_yaml = yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = "mgmt"
      cluster = {
        server                       = data.aws_ssm_parameter.api_endpoint.value
        "certificate-authority-data" = data.aws_ssm_parameter.ca_cert.value
      }
    }]
    users = [{
      name = "mgmt"
      user = { token = data.aws_ssm_parameter.token.value }
    }]
    contexts = [{
      name    = "mgmt"
      context = { cluster = "mgmt", user = "mgmt" }
    }]
    "current-context" = "mgmt"
  })
}

# ── Root Application Bootstrap（環境入口點）────────────────────────────────────
# 套用對應環境的 Root Application（App of Apps），讓 ArgoCD 開始管理該環境的所有應用。
# 這個 root 假設 install root（Worker Cluster Secret）與 self-manage root（self-managed
# Application）都已完成 apply；三個 root 的順序由 workflow 保證
# （install → self-manage → ateam，見 .github/workflows/ 下 apply workflows 的
# needs 鏈），不靠 Terraform 跨 state 的 depends_on。
# Application 納入 Terraform state，因此刪除或 drift 會在 plan 中被偵測。
resource "kustomization_resource" "argocd_root_app" {
  for_each = local.environment_config.root_applications

  manifest = jsonencode(yamldecode(
    file("${local.manifest_root}/bootstrap/${each.value.manifest}")
  ))

  lifecycle {
    precondition {
      condition = (
        yamldecode(
          file("${local.manifest_root}/bootstrap/${each.value.manifest}")
        ).metadata.name == each.value.name
      )
      error_message = "The Root Application name must match manifest metadata.name."
    }
  }
}
