output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "karpenter_interruption_queue" {
  value = module.karpenter.queue_name
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster."
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}${var.aws_profile == null ? "" : " --profile ${var.aws_profile}"}"
}

output "argocd_ui" {
  description = "Open the ArgoCD UI at http://localhost:8080 (user: admin)."
  value       = "kubectl -n argocd port-forward svc/argocd-server 8080:80"
}

output "argocd_admin_password" {
  description = "Command that prints the initial ArgoCD admin password."
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
}
