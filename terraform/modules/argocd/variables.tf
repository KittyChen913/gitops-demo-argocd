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
  description = "是否建立僅供 VPN 使用的 Argo CD private endpoint。"
  type        = bool
  default     = false
}

variable "argocd_internal_fqdn" {
  description = "VPN 用戶端連線 Argo CD UI 使用的內部 FQDN。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.argocd_internal_fqdn))
    error_message = "啟用 private network 時，argocd_internal_fqdn 必須是小寫 FQDN。"
  }
}

variable "openvpn_server_public_ipv4" {
  description = "OpenVPN server 對 Argo CD 流量執行 SNAT 時使用的固定公有 IPv4。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(cidrnetmask("${var.openvpn_server_public_ipv4}/32"))
    error_message = "啟用 private network 時，openvpn_server_public_ipv4 必須是未帶 CIDR suffix 的 IPv4。"
  }
}

variable "openvpn_server_public_ipv6" {
  description = "OpenVPN 選用的固定公有 IPv6；省略時不啟用 IPv6 ingress。"
  type        = string
  default     = null

  validation {
    condition     = var.openvpn_server_public_ipv6 == null ? true : can(cidrhost("${var.openvpn_server_public_ipv6}/128", 0))
    error_message = "openvpn_server_public_ipv6 必須是 null 或未帶 CIDR suffix 的 IPv6。"
  }
}

variable "openvpn_tunnel_cidr" {
  description = "OpenVPN 用戶端使用的 IPv4 CIDR，作為 DNS 與 routing trust boundary。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(cidrnetmask(var.openvpn_tunnel_cidr))
    error_message = "啟用 private network 時，openvpn_tunnel_cidr 必須是有效的 IPv4 CIDR。"
  }
}

variable "internal_dns_server_ip" {
  description = "只能透過 OpenVPN 通道連線的 DNS resolver IPv4。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(cidrnetmask("${var.internal_dns_server_ip}/32"))
    error_message = "啟用 private network 時，internal_dns_server_ip 必須是未帶 CIDR suffix 的 IPv4。"
  }
}

variable "argocd_load_balancer_ipv4" {
  description = "預先保留並指派給專用 Argo CD NodeBalancer 的 Linode IPv4。"
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(cidrnetmask("${var.argocd_load_balancer_ipv4}/32"))
    error_message = "啟用 private network 時，argocd_load_balancer_ipv4 必須是未帶 CIDR suffix 的 IPv4。"
  }
}

variable "argocd_https_port" {
  description = "專用 Argo CD NodeBalancer 公開的 HTTPS listener port。"
  type        = number
  default     = 443

  validation {
    condition     = var.argocd_https_port >= 1 && var.argocd_https_port <= 65535
    error_message = "argocd_https_port 必須介於 1 與 65535。"
  }
}


