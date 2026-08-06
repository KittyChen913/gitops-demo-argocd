locals {
  environment_config = jsondecode(file("${path.module}/../../environments/dev.json"))
  private_network    = local.environment_config.private_network
  argocd_namespace   = "argocd"
}

# 這個 root 只管理 VPN-only ArgoCD private entry；desired state 裡固定假設
# private_network.enabled = true。使用 lifecycle precondition 讓契約錯誤直接
# 阻止 plan／apply，不以只產生 warning 的 check block 或 count no-op 處理。
resource "terraform_data" "private_network_contract" {
  lifecycle {
    precondition {
      condition     = local.private_network.enabled
      error_message = "The private-network root requires private_network.enabled to be true."
    }

    precondition {
      condition     = contains(["dev", "prod"], local.private_network.environment)
      error_message = "private_network.environment must be dev or prod."
    }

    precondition {
      condition     = can(regex("^[a-z]{2}-[a-z]+$", local.private_network.linode_region))
      error_message = "private_network.linode_region must be a valid Linode region identifier."
    }

    precondition {
      condition     = can(regex("^/gitops/platform-access/network/INTERNAL_DOMAIN$", local.private_network.internal_domain_parameter_name))
      error_message = "INTERNAL_DOMAIN must be read from the approved Platform Access SSM path."
    }

    precondition {
      condition     = can(regex("^/gitops/platform-access/network/VPN_PUBLIC_EGRESS_IP$", local.private_network.vpn_public_egress_ip_parameter_name))
      error_message = "VPN egress must be read from the approved Platform Access SSM path."
    }

    precondition {
      condition     = local.private_network.endpoint_ip_parameter_name == "/gitops/${local.private_network.environment}/platform/argocd/ENDPOINT_IP"
      error_message = "The endpoint IP parameter must match the environment."
    }

    precondition {
      condition     = local.private_network.endpoint_hostname_parameter_name == "/gitops/${local.private_network.environment}/platform/argocd/ENDPOINT_HOSTNAME"
      error_message = "The endpoint hostname parameter must match the environment."
    }

    precondition {
      condition     = local.private_network.argocd_https_port == 443
      error_message = "The VPN-only ArgoCD private endpoint must use TCP/443."
    }

    precondition {
      condition     = local.private_network.argocd_tls_secret_name == "argocd-server-tls"
      error_message = "The private endpoint must reuse argocd-server-tls without copying the TLS private key."
    }

    precondition {
      condition     = local.private_network.openvpn_server_public_ipv6 == null
      error_message = "The private endpoint does not support IPv6 ingress; openvpn_server_public_ipv6 must be null."
    }
  }
}

# ── SSM Parameter Store：Management Cluster 連線資訊（供 kubernetes provider 使用）──
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

# ── Platform Access 跨 Repository hand-off ─────────────────────────────────
# 只讀取精確 parameter 名稱；不讀取另一個 Repository 的 Terraform state。
data "aws_ssm_parameter" "internal_domain" {
  name = local.private_network.internal_domain_parameter_name
}

data "aws_ssm_parameter" "vpn_public_egress_ip" {
  name = local.private_network.vpn_public_egress_ip_parameter_name
}

locals {
  # AWS provider 對 aws_ssm_parameter data source 的 value 一律標記為 sensitive，
  # 不論 parameter type；internal_domain 只是網域名稱，非機密，故用 nonsensitive()
  # 還原，讓 argocd_network_config output 能維持原設計的非機密 hand-off 契約。
  internal_domain      = nonsensitive(trimspace(data.aws_ssm_parameter.internal_domain.value))
  argocd_internal_fqdn = "argocd.${local.private_network.environment}.internal.${local.internal_domain}"
  vpn_public_egress_ip = trimspace(data.aws_ssm_parameter.vpn_public_egress_ip.value)
}

# Dev／Prod 各自的 state 擁有一個專用 Reserved IPv4。CCM 只負責把該位址綁到
# companion Service 所建立的 NodeBalancer，不從 versioned config 複製 public IP。
resource "linode_networking_ip" "argocd_private" {
  type     = "ipv4"
  public   = true
  reserved = true
  region   = local.private_network.linode_region

  lifecycle {
    prevent_destroy = true
  }
}

# 專用的 VPN-only 入口。既有 argocd-server ClusterIP Service 由 ArgoCD Kustomize
# installation 管理（terraform/argocd/dev/install/main.tf 另一份 state）；
# 此 companion Service 只由 Terraform 管理，避免 ArgoCD 與 Terraform 協調同一個
# Kubernetes object。namespace 假設已由 install stage 建立；兩個 root 之間的
# 順序由 workflow 保證，不靠 Terraform 跨 state 的 depends_on。
resource "kubernetes_service_v1" "argocd_server_private" {
  metadata {
    name      = "argocd-server-private"
    namespace = local.argocd_namespace

    labels = {
      "app.kubernetes.io/component"  = "server"
      "app.kubernetes.io/name"       = "argocd-server-private"
      "app.kubernetes.io/part-of"    = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }

    annotations = {
      "service.beta.kubernetes.io/linode-loadbalancer-default-protocol" = "tcp"
      "service.beta.kubernetes.io/linode-loadbalancer-check-type"       = "connection"
      "service.beta.kubernetes.io/linode-loadbalancer-check-interval"   = "5"
      "service.beta.kubernetes.io/linode-loadbalancer-check-timeout"    = "3"
      "service.beta.kubernetes.io/linode-loadbalancer-check-attempts"   = "2"
      "service.beta.kubernetes.io/linode-loadbalancer-reserved-ipv4"    = linode_networking_ip.argocd_private.address
      "service.beta.kubernetes.io/linode-loadbalancer-tags"             = "argocd,internal,vpn-only"
      "service.beta.kubernetes.io/linode-loadbalancer-firewall-acl" = jsonencode({
        allowList = {
          ipv4 = ["${local.vpn_public_egress_ip}/32"]
        }
      })
    }
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
      port        = local.private_network.argocd_https_port
      target_port = "8080"
    }
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition = (
        can(cidrnetmask("${local.vpn_public_egress_ip}/32")) &&
        can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", local.argocd_internal_fqdn)) &&
        local.private_network.argocd_https_port == 443 &&
        local.private_network.openvpn_server_public_ipv6 == null
      )
      error_message = "The private endpoint requires a valid VPN egress /32, lowercase internal FQDN, TCP/443, and no IPv6 ingress."
    }
  }
}

# Endpoint publication 是非敏感的跨 Repository 介面。Platform Access 只讀取這兩個
# parameter，不讀取 infra state；prevent_destroy 避免默默刪除 contract。
resource "aws_ssm_parameter" "argocd_endpoint_ip" {
  name  = local.private_network.endpoint_ip_parameter_name
  type  = "String"
  value = linode_networking_ip.argocd_private.address

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "argocd_endpoint_hostname" {
  name  = local.private_network.endpoint_hostname_parameter_name
  type  = "String"
  value = local.argocd_internal_fqdn

  lifecycle {
    prevent_destroy = true
  }
}
