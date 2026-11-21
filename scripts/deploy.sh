#!/usr/bin/env bash
# Phase 2 - deploy. Run from the project root:  ./scripts/deploy.sh
set -euo pipefail

PROFILE="${AWS_PROFILE_NAME:-portfolio-sandbox}"
REGION="${AWS_REGION:-us-east-1}"
cd "$(dirname "$0")/../terraform"

echo "== Pre-flight =="
for bin in terraform aws kubectl; do
  command -v "$bin" >/dev/null || { echo "Missing: $bin"; exit 1; }
done
aws sts get-caller-identity --profile "$PROFILE" --query '{Account:Account,Arn:Arn}' --output table

cat <<'EOF'

== Estimated hourly cost (us-east-1, on-demand list prices) ==
  EKS control plane (standard support)      $0.100
  NAT Gateway (1x, + $0.045/GB processed)   $0.045
  Public IPv4 for NAT (1x)                  $0.005
  2x t3.medium system nodes                 $0.083
  2x 20 GB gp3 root volumes                 $0.002
  SQS / EventBridge / CloudWatch logs       ~$0.001
  ------------------------------------------------
  Baseline                                  ~$0.24/hr  (~$5.70/day)
  + Karpenter Spot nodes during the demo    ~$0.01-0.05/hr each
  None of these are Free Tier. Run ./scripts/destroy-and-verify.sh when done.

EOF
read -r -p "Proceed with terraform apply? [y/N] " ok
[[ "$ok" =~ ^[Yy]$ ]] || exit 0

terraform init -upgrade
terraform fmt -recursive
terraform validate
terraform apply -auto-approve

echo "== Health checks =="
aws eks update-kubeconfig --name "$(terraform output -raw cluster_name)" --region "$REGION" --profile "$PROFILE"
kubectl get nodes -o wide
kubectl -n kube-system rollout status deploy/karpenter --timeout=180s
kubectl get nodepools,ec2nodeclasses
kubectl -n argocd get pods
kubectl -n argocd get applications

echo
echo "Karpenter demo:"
echo "  kubectl apply -f ../k8s/inflate.yaml && kubectl scale deploy inflate --replicas=10"
echo "  kubectl get nodeclaims -w"
echo "ArgoCD UI:"
echo "  $(terraform output -raw argocd_ui)   ->  http://localhost:8080"
echo "  password: $(terraform output -raw argocd_admin_password)"
