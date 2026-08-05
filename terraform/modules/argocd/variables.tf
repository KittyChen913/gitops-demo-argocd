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
  description = "Whether to apply the private endpoint canonical URL and RBAC patch to the self-managed Application."
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

variable "internal_domain_parameter_name" {
  description = "Exact SSM parameter name for the Internal DNS INTERNAL_DOMAIN published by Platform Access."
  type        = string
  default     = ""

  validation {
    condition     = !var.private_network_enabled || can(regex("^/gitops/platform-access/network/INTERNAL_DOMAIN$", var.internal_domain_parameter_name))
    error_message = "INTERNAL_DOMAIN must be read from the approved Platform Access SSM path."
  }
}

variable "argocd_internal_fqdn" {
  description = "VPN 用戶端連線 ArgoCD UI 使用的內部 FQDN。"
  type        = string
  default     = ""

  validation {
    condition = (
      !var.private_network_enabled ||
      var.internal_domain_parameter_name != "" ||
      can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$", var.argocd_internal_fqdn))
    )
    error_message = "When private network is enabled, provide the INTERNAL_DOMAIN SSM path or a valid lowercase FQDN."
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
