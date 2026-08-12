locals {
  environment_config = jsondecode(file("${path.module}/../../environments/prod.json"))
  private_network    = local.environment_config.private_network
  manifest_root      = abspath("${path.module}/../../../../argocd")
}

# 這個 root 只管理 self-managed Application；desired state 裡固定假設
# environment_config 的 schema 已由 gitops-demo-argocd 的 CI（load-environment-config
# action 的 jq 檢查）與 install root 共用同一份 environments/<env>.json 驗證過。
# 這裡再加一層 fail-closed 的 lifecycle precondition，避免這個獨立 state 在
# schema 被改壞時仍以 exit 0 通過 plan gate（同 private-network root 的做法，
# 見 terraform/argocd/prod/private-network/main.tf）。
resource "terraform_data" "self_manage_contract" {
  lifecycle {
    precondition {
      condition     = !local.private_network.enabled || contains(["dev", "prod"], local.private_network.environment)
      error_message = "When private network is enabled, private_network.environment must be dev or prod."
    }

    precondition {
      condition     = !local.private_network.enabled || can(regex("^/gitops/openvpn-dns/network/INTERNAL_DOMAIN$", local.private_network.internal_domain_parameter_name))
      error_message = "INTERNAL_DOMAIN must be read from the approved OpenVPN/DNS SSM path."
    }
  }
}

# ── SSM Parameter Store：lke-prod-mgmt 連線資訊（供 kustomization provider 使用）──
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

# ── OpenVPN／DNS 跨 Repository hand-off ─────────────────────────────────
# 只讀取精確 parameter 名稱；不讀取另一個 Repository 的 Terraform state。
# 這裡只讀 INTERNAL_DOMAIN 是為了組出 self-managed Application 的 canonical URL
# patch；private-network 專用資源已在 terraform/argocd/prod/private-network/
# 這個獨立 root 與 state 管理。
data "aws_ssm_parameter" "internal_domain" {
  count = local.private_network.enabled ? 1 : 0
  name  = local.private_network.internal_domain_parameter_name
}

locals {
  # AWS provider 對 aws_ssm_parameter data source 的 value 一律標記為 sensitive，
  # 不論 parameter type；internal_domain 只是網域名稱，非機密，故用 nonsensitive()
  # （與 terraform/argocd/prod/private-network/main.tf 的既有作法一致）。
  internal_domain = local.private_network.enabled ? nonsensitive(trimspace(data.aws_ssm_parameter.internal_domain[0].value)) : ""
  argocd_internal_fqdn = local.private_network.enabled ? (
    "argocd.${local.private_network.environment}.internal.${local.internal_domain}"
  ) : ""

  argocd_self_app_manifest = local.private_network.enabled ? templatefile(
    "${local.manifest_root}/bootstrap/argocd-app-${local.private_network.environment}.yaml.tftpl",
    {
      argocd_internal_fqdn = local.argocd_internal_fqdn
    }
  ) : file("${local.manifest_root}/bootstrap/argocd-app.yaml")

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

# ── ArgoCD 自我管理 Application 初始化 ──────────────────────────────────────
# 由 Terraform provider 直接管理 Application，讓 plan 可偵測刪除與 drift。
# 這個 root 假設 install root（terraform/argocd/prod/install，另一份 state）
# 已完成 ArgoCD CRD 安裝；兩個 root 之間的順序由 workflow 保證，不靠 Terraform
# 跨 state 的 depends_on（與 private-network root 對 install 的既有作法一致）。
resource "kustomization_resource" "argocd_self_app" {
  manifest = jsonencode(yamldecode(local.argocd_self_app_manifest))
}
