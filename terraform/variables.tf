variable "project_name" {
  description = "Name prefix for every resource (also the EKS cluster name)."
  type        = string
  default     = "eks-karpenter-argocd"
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Named AWS CLI profile. Set to null to use environment credentials (e.g. in CI)."
  type        = string
  default     = "portfolio-sandbox"
}

variable "kubernetes_version" {
  description = "EKS control-plane version. Keep this on a version in EKS *standard* support to avoid the $0.60/hr extended-support fee."
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Lock this to your IP (x.x.x.x/32) for real use."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "system_node_instance_type" {
  description = "Instance type for the small managed node group that runs Karpenter, CoreDNS and ArgoCD."
  type        = string
  default     = "m7i-flex.large"
}

variable "free_plan_account" {
  description = "True for AWS Free plan accounts: restricts every EC2 instance (system nodes and Karpenter nodes) to free-tier eligible types."
  type        = bool
  default     = true
}

variable "karpenter_version" {
  description = "Karpenter Helm chart version (must support var.kubernetes_version - see karpenter.sh compatibility matrix)."
  type        = string
  default     = "1.15.0"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version from argoproj.github.io/argo-helm."
  type        = string
  default     = "9.1.0"
}

variable "gitops_repo_url" {
  description = "Git repository ArgoCD syncs the demo application from."
  type        = string
  default     = "https://github.com/argoproj/argocd-example-apps.git"
}

variable "gitops_repo_path" {
  description = "Path inside gitops_repo_url that holds the app manifests."
  type        = string
  default     = "guestbook"
}
