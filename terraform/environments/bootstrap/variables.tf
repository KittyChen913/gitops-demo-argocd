variable "tf_state_bucket" {
  description = "S3 bucket name for Terraform remote state backend."
  type        = string
  default     = "kc-gitops-demo-tfstate"
}

variable "aws_region" {
  description = "AWS region for the S3 State Bucket."
  type        = string
  default     = "ap-southeast-1"
}
