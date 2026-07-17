# ── SSM Parameter Store：lke-dev-mgmt 連線資訊 ────────────────────────────────
# 路徑格式：${ssm_path_prefix}/${mgmt_cluster_label}/<param>
data "aws_ssm_parameter" "api_endpoint" {
  name = "${var.ssm_path_prefix}/${var.mgmt_cluster_label}/api-endpoint"
}

data "aws_ssm_parameter" "ca_cert" {
  name = "${var.ssm_path_prefix}/${var.mgmt_cluster_label}/ca-cert"
}

# token 為 SecureString，需啟用解密
data "aws_ssm_parameter" "token" {
  name            = "${var.ssm_path_prefix}/${var.mgmt_cluster_label}/token"
  with_decryption = true
}

# ── SSM Parameter Store：Worker Cluster 連線資訊 ──────────────────────────────
# 路徑格式：${ssm_path_prefix}/${worker_cluster_label}/<param>
data "aws_ssm_parameter" "worker_api_endpoint" {
  name = "${var.ssm_path_prefix}/${var.worker_cluster_label}/api-endpoint"
}

data "aws_ssm_parameter" "worker_ca_cert" {
  name = "${var.ssm_path_prefix}/${var.worker_cluster_label}/ca-cert"
}

data "aws_ssm_parameter" "worker_token" {
  name            = "${var.ssm_path_prefix}/${var.worker_cluster_label}/token"
  with_decryption = true
}

# ── Management Cluster kubeconfig（供 kustomization provider 使用）────────────
locals {
  manifest_root = abspath("${path.module}/../../../argocd")

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
    name = var.argocd_namespace
  }
}

# 專用的 VPN-only 入口。既有 argocd-server ClusterIP Service 仍由 Argo CD
# Kustomize installation 管理；此 companion Service 只由 Terraform 管理，
# 避免 Argo CD 與 Terraform 協調同一個 Kubernetes object。
resource "kubernetes_service_v1" "argocd_server_private" {
  count = var.private_network_enabled ? 1 : 0

  metadata {
    name      = "argocd-server-private"
    namespace = var.argocd_namespace

    labels = {
      "app.kubernetes.io/component"  = "server"
      "app.kubernetes.io/name"       = "argocd-server-private"
      "app.kubernetes.io/part-of"    = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }

    annotations = merge(
      {
        "service.beta.kubernetes.io/linode-loadbalancer-default-protocol" = "tcp"
        "service.beta.kubernetes.io/linode-loadbalancer-check-type"       = "connection"
        "service.beta.kubernetes.io/linode-loadbalancer-check-interval"   = "5"
        "service.beta.kubernetes.io/linode-loadbalancer-check-timeout"    = "3"
        "service.beta.kubernetes.io/linode-loadbalancer-check-attempts"   = "2"
        "service.beta.kubernetes.io/linode-loadbalancer-reserved-ipv4"    = var.argocd_load_balancer_ipv4
        "service.beta.kubernetes.io/linode-loadbalancer-tags"             = "argocd,internal,vpn-only"
        "service.beta.kubernetes.io/linode-loadbalancer-firewall-acl" = jsonencode({
          allowList = merge(
            { ipv4 = ["${var.openvpn_server_public_ipv4}/32"] },
            var.openvpn_server_public_ipv6 == null ? {} : {
              ipv6 = ["${var.openvpn_server_public_ipv6}/128"]
            }
          )
        })
      },
      var.openvpn_server_public_ipv6 == null ? {} : {
        "service.beta.kubernetes.io/linode-loadbalancer-enable-ipv6-ingress" = "true"
      }
    )
  }

  spec {
    type                    = "LoadBalancer"
    external_traffic_policy = "Cluster"

    selector = {
      "app.kubernetes.io/name" = "argocd-server"
    }

    port {
      name        = "https"
      protocol    = "TCP"
      port        = var.argocd_https_port
      target_port = "8080"
    }
  }

}

# 只管理既有 Argo CD ConfigMap 的 canonical URL 欄位。Kustomize installation
# 仍擁有 ConfigMap object 與其他 data，Terraform 則透過 SSA 管理此環境欄位。
resource "kubernetes_config_map_v1_data" "argocd_cm_url" {
  count = var.private_network_enabled ? 1 : 0

  metadata {
    name      = "argocd-cm"
    namespace = var.argocd_namespace
  }

  data = {
    url = "https://${var.argocd_internal_fqdn}"
  }

  field_manager = "terraform-argocd-network"
  force         = true
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
    # 首次 bootstrap 後由 Argo CD 接手 install manifests 的 reconciliation。
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
    # 後續升級與 drift 修復由 self-managed Argo CD Application 負責。
    ignore_changes = [manifest]
  }
}

# ── ArgoCD Cluster Secret（Worker Cluster 註冊）────────────────────────────────
# 在 Management Cluster 的 argocd namespace 建立 Cluster Secret，
# ArgoCD 透過此 Secret 連線管理 Worker Cluster。
# 格式參考：https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters
resource "kubernetes_secret_v1" "argocd_worker_cluster" {
  metadata {
    name      = "cluster-${var.worker_cluster_label}"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "app.kubernetes.io/part-of"      = "gitops-demo"
    }
  }

  data = {
    name   = var.worker_cluster_label
    server = data.aws_ssm_parameter.worker_api_endpoint.value
    config = jsonencode({
      bearerToken = data.aws_ssm_parameter.worker_token.value
      tlsClientConfig = {
        caData = data.aws_ssm_parameter.worker_ca_cert.value
      }
    })
  }
}

# ── ArgoCD 自我管理 Application 初始化 ──────────────────────────────────────
# 由 Terraform provider 直接管理 Application，讓 plan 可偵測刪除與 drift。
resource "kustomization_resource" "argocd_self_app" {
  manifest = jsonencode(yamldecode(
    file("${local.manifest_root}/bootstrap/argocd-app.yaml")
  ))
}

# ── Root Application Bootstrap（環境入口點）────────────────────────────────────
# 套用對應環境的 Root Application（App of Apps），讓 ArgoCD 開始管理該環境的所有應用。
# 須在 argocd_self_app 之後執行，確保 ArgoCD CRD 已就緒。
# Application 納入 Terraform state，因此刪除或 drift 會在 plan 中被偵測。
resource "kustomization_resource" "argocd_root_app" {
  for_each = var.root_applications

  manifest = jsonencode(yamldecode(
    file("${local.manifest_root}/bootstrap/${each.value.manifest}")
  ))
  depends_on = [
    kubernetes_secret_v1.argocd_worker_cluster,
    kustomization_resource.argocd_self_app,
  ]

  lifecycle {
    precondition {
      condition = (
        yamldecode(
          file("${local.manifest_root}/bootstrap/${each.value.manifest}")
        ).metadata.name == each.value.name
      )
      error_message = "Root Application 設定名稱必須與 manifest metadata.name 相同。"
    }
  }
}
