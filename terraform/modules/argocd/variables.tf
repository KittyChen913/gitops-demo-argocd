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


