terraform {
  backend "s3" {
    bucket       = "kc-gitops-demo-tfstate"
    region       = "ap-southeast-1"
    key          = "gitops-demo-argocd/prod/argocd-ateam/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
