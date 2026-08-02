variable "aws_region" {
  description = "AWS region（SSM Parameter Store 所在區域）"
  type        = string
  default     = "ap-southeast-1"
}

variable "ssm_path_prefix" {
  description = "SSM Parameter Store 路徑前綴，例如 /k8s/clusters"
  type        = string
  default     = "/k8s/clusters"
}

variable "mgmt_cluster_label" {
  description = "Management Cluster 標籤，對應 SSM 路徑中的 cluster 名稱（例如 lke-dev-mgmt）"
  type        = string
}

variable "worker_cluster_label" {
  description = "Worker Cluster 標籤，對應 SSM 路徑中的 cluster 名稱（例如 lke-dev-ateam）"
  type        = string
}

variable "argocd_namespace" {
  description = "ArgoCD 部署的 Kubernetes namespace"
  type        = string
  default     = "argocd"
}

variable "root_applications" {
  description = "各 team 的 Root Application metadata，manifest 路徑相對於 argocd/bootstrap/"
  type = map(object({
    name     = string
    manifest = string
  }))
  default = {}
}

variable "private_network_enabled" {
  description = "是否建立僅供 VPN 使用的 ArgoCD private endpoint。"
  type        = bool
  default     = false
}

variable "deployment_environment" {
  description = "Private endpoint所屬環境；只允許Dev或Prod。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || contains(["dev", "prod"], var.deployment_environment)
    error_message = "啟用private network時，deployment_environment必須是dev或prod。"
  }
}

variable "linode_region" {
  description = "Reserved IPv4與Management Cluster所在的Linode region。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(regex("^[a-z]{2}-[a-z]+$", var.linode_region))
    error_message = "啟用private network時，linode_region必須是有效的Linode region識別字。"
  }
}

variable "base_domain_parameter_name" {
  description = "Platform Access發布Internal DNS BASE_DOMAIN的精確SSM parameter名稱。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(regex("^/gitops/platform-access/network/BASE_DOMAIN$", var.base_domain_parameter_name))
    error_message = "BASE_DOMAIN必須由核准的Platform Access SSM path讀取。"
  }
}

variable "vpn_public_egress_ip_parameter_name" {
  description = "Platform Access發布固定VPN public egress IPv4的精確SSM parameter名稱。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(regex("^/gitops/platform-access/network/VPN_PUBLIC_EGRESS_IP$", var.vpn_public_egress_ip_parameter_name))
    error_message = "VPN egress必須由核准的Platform Access SSM path讀取。"
  }
}

variable "endpoint_ip_parameter_name" {
  description = "Infra發布ArgoCD private endpoint IPv4的精確SSM parameter名稱。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || var.endpoint_ip_parameter_name == "/gitops/${var.deployment_environment}/platform/argocd/ENDPOINT_IP"
    error_message = "Endpoint IP parameter必須與deployment_environment一致。"
  }
}

variable "endpoint_hostname_parameter_name" {
  description = "Infra發布ArgoCD private endpoint hostname的精確SSM parameter名稱。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || var.endpoint_hostname_parameter_name == "/gitops/${var.deployment_environment}/platform/argocd/ENDPOINT_HOSTNAME"
    error_message = "Endpoint hostname parameter必須與deployment_environment一致。"
  }
}

variable "argocd_internal_fqdn" {
  description = "VPN 用戶端連線 ArgoCD UI 使用的內部 FQDN。"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.private_network_enabled ||
      var.base_domain_parameter_name != "" ||
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.argocd_internal_fqdn))
    )
    error_message = "啟用private network時，必須提供BASE_DOMAIN SSM path或有效的小寫FQDN。"
  }
}

variable "openvpn_server_public_ipv4" {
  description = "OpenVPN server 對 ArgoCD 流量執行 SNAT 時使用的固定公有 IPv4。"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.private_network_enabled ||
      var.vpn_public_egress_ip_parameter_name != "" ||
      can(cidrnetmask("${var.openvpn_server_public_ipv4}/32"))
    )
    error_message = "啟用private network時，必須提供VPN egress SSM path或未帶CIDR suffix的IPv4。"
  }
}

variable "openvpn_server_public_ipv6" {
  description = "OpenVPN 選用的固定公有 IPv6；省略時不啟用 IPv6 ingress。"
  type        = string
  default     = null

  validation {
    condition = (
      var.openvpn_server_public_ipv6 == null &&
      (!var.private_network_enabled || var.openvpn_server_public_ipv6 == null)
    )
    error_message = "Private endpoint不啟用IPv6 ingress；openvpn_server_public_ipv6必須是null。"
  }
}

variable "openvpn_tunnel_cidr" {
  description = "OpenVPN 用戶端使用的 IPv4 CIDR，作為 DNS 與 routing trust boundary。"
  type        = string
  default     = ""

  validation {
    condition     = var.openvpn_tunnel_cidr == "" || can(cidrnetmask(var.openvpn_tunnel_cidr))
    error_message = "openvpn_tunnel_cidr必須為空或有效的IPv4 CIDR。"
  }
}

variable "internal_dns_server_ip" {
  description = "只能透過 OpenVPN 通道連線的 DNS resolver IPv4。"
  type        = string
  default     = ""

  validation {
    condition     = var.internal_dns_server_ip == "" || can(cidrnetmask("${var.internal_dns_server_ip}/32"))
    error_message = "internal_dns_server_ip必須為空或未帶CIDR suffix的IPv4。"
  }
}

variable "argocd_load_balancer_ipv4" {
  description = "預先保留並指派給專用 ArgoCD NodeBalancer 的 Linode IPv4。"
  type        = string
  default     = ""

  validation {
    condition     = var.argocd_load_balancer_ipv4 == "" || can(cidrnetmask("${var.argocd_load_balancer_ipv4}/32"))
    error_message = "argocd_load_balancer_ipv4必須為空或未帶CIDR suffix的IPv4。"
  }
}

variable "argocd_https_port" {
  description = "專用 ArgoCD NodeBalancer 公開的 HTTPS listener port。"
  type        = number
  default     = 443

  validation {
    condition     = !var.private_network_enabled || var.argocd_https_port == 443
    error_message = "VPN-only ArgoCD private endpoint只允許TCP/443。"
  }
}

variable "argocd_tls_secret_name" {
  description = "ArgoCD server Pod終止TLS所使用的既有Secret reference。"
  type        = string
  default     = "argocd-server-tls"

  validation {
    condition     = !var.private_network_enabled || var.argocd_tls_secret_name == "argocd-server-tls"
    error_message = "Private endpoint必須沿用argocd-server-tls，不得複製TLS private key。"
  }
}


