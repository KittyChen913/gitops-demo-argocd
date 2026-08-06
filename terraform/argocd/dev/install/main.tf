locals {
  environment_config = jsondecode(file("${path.module}/../../environments/dev.json"))
  manifest_root      = abspath("${path.module}/../../../../argocd")
  argocd_namespace   = "argocd"
}

# ── SSM Parameter Store：lke-dev-mgmt 連線資訊 ────────────────────────────────
# 路徑格式：${ssm_path_prefix}/${mgmt_cluster_label}/<param>
data "aws_ssm_parameter" "api_endpoint" {
  name = "${local.environment_config.ssm_path_prefix}/${local.environment_config.mgmt_cluster_label}/api-endpoint"
}

data "aws_ssm_parameter" "ca_cert" {
  name = "${local.environment_config.ssm_path_prefix}/${local.environment_config.mgmt_cluster_label}/ca-cert"
}

# token 為 SecureString，需啟用解密
data "aws_ssm_parameter" "token" {
  name            = "${local.environment_config.ssm_path_prefix}/${local.environment_config.mgmt_cluster_label}/token"
  with_decryption = true
}

# ── SSM Parameter Store：Worker Cluster 連線資訊 ──────────────────────────────
# 路徑格式：${ssm_path_prefix}/${worker_cluster_label}/<param>
data "aws_ssm_parameter" "worker_api_endpoint" {
  name = "${local.environment_config.ssm_path_prefix}/${local.environment_config.worker_cluster_label}/api-endpoint"
}

data "aws_ssm_parameter" "worker_ca_cert" {
  name = "${local.environment_config.ssm_path_prefix}/${local.environment_config.worker_cluster_label}/ca-cert"
}

data "aws_ssm_parameter" "worker_token" {
  name            = "${local.environment_config.ssm_path_prefix}/${local.environment_config.worker_cluster_label}/token"
  with_decryption = true
}

# ── Management Cluster kubeconfig（供 kustomization provider 使用）────────────
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

# ── ArgoCD 命名空間 ──────────────────────────────────────────────────────────
# 明確建立 namespace，確保在所有 kustomize 資源前就存在，
# 避免 kbst provider 平行建立時 ConfigMap 找不到 namespace 的競態問題。
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = local.argocd_namespace
  }
}

# ── ArgoCD 安裝（Kustomize）────────────────────────────────────────────────────
# 透過 kbst/kustomization provider 套用 argocd/install/ 目錄。
# priority group 0：CRDs（最優先）
# priority group 1：ClusterRole、ClusterRoleBinding 等 cluster-scoped 資源
# priority group 2：Deployment、Service 等 namespace-scoped 資源
data "kustomization_build" "argocd_install" {
  path = "${local.manifest_root}/install"
}

resource "kustomization_resource" "argocd_p0" {
  for_each   = data.kustomization_build.argocd_install.ids_prio[0]
  manifest   = data.kustomization_build.argocd_install.manifests[each.value]
  depends_on = [kubernetes_namespace_v1.argocd]

  lifecycle {
    # 首次 bootstrap 後由 ArgoCD 接手 install manifests 的 reconciliation。
    ignore_changes = [manifest]
  }
}

resource "kustomization_resource" "argocd_p1" {
  for_each   = data.kustomization_build.argocd_install.ids_prio[1]
  manifest   = data.kustomization_build.argocd_install.manifests[each.value]
  depends_on = [kustomization_resource.argocd_p0]

  lifecycle {
    # 避免 kbst provider 以缺失的 last-applied annotation 更新既有資源。
    ignore_changes = [manifest]
  }
}

resource "kustomization_resource" "argocd_p2" {
  for_each   = data.kustomization_build.argocd_install.ids_prio[2]
  manifest   = data.kustomization_build.argocd_install.manifests[each.value]
  depends_on = [kustomization_resource.argocd_p1]

  lifecycle {
    # 後續升級與 drift 修復由 self-managed ArgoCD Application 負責。
    ignore_changes = [manifest]
  }
}

# ── ArgoCD Cluster Secret（Worker Cluster 註冊）────────────────────────────────
# 在 Management Cluster 的 argocd namespace 建立 Cluster Secret，
# ArgoCD 透過此 Secret 連線管理 Worker Cluster。
# 格式參考：https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters
#
# 擁有權說明：在舊的單一 state／-target 設計裡，這個資源從未被列在任何一組
# -target 清單中，只因為是 ateam stage 的 -target=...argocd_root_app 的隱性
# 依賴（terraform apply -target 會自動納入目標的依賴鏈）才被套用。這次拆分
# state 時明確把它歸戶到 install root：cluster registration 屬於平台安裝的
# 一部分，變更頻率與 install 相近，不應隨每次 ateam Application 變更而重新
# 評估或漂移偵測。
resource "kubernetes_secret_v1" "argocd_worker_cluster" {
  metadata {
    name      = "cluster-${local.environment_config.worker_cluster_label}"
    namespace = local.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "app.kubernetes.io/part-of"      = "gitops-demo"
    }
  }

  data = {
    name   = local.environment_config.worker_cluster_label
    server = data.aws_ssm_parameter.worker_api_endpoint.value
    config = jsonencode({
      bearerToken = data.aws_ssm_parameter.worker_token.value
      tlsClientConfig = {
        caData = data.aws_ssm_parameter.worker_ca_cert.value
      }
    })
  }

  depends_on = [kustomization_resource.argocd_p2]
}
