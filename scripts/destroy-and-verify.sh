#!/usr/bin/env bash
# Phase 4 - destroy and prove zero orphaned billable resources.
# Run from the project root:  ./scripts/destroy-and-verify.sh
set -uo pipefail

PROFILE="${AWS_PROFILE_NAME:-portfolio-sandbox}"
REGION="${AWS_REGION:-us-east-1}"
NAME="${PROJECT_NAME:-eks-karpenter-argocd}"
AWS="aws --profile $PROFILE --region $REGION"
cd "$(dirname "$0")/../terraform"

echo "== 1. Drain Kubernetes-created AWS resources (Terraform does not own these) =="
if $AWS eks describe-cluster --name "$NAME" >/dev/null 2>&1; then
  $AWS eks update-kubeconfig --name "$NAME" >/dev/null
  kubectl delete deploy inflate --ignore-not-found
  kubectl -n argocd delete application guestbook --ignore-not-found --wait=true --timeout=180s
  # Any Service of type LoadBalancer would leave an orphan ELB - remove them first.
  kubectl get svc -A -o json | jq -r '.items[] | select(.spec.type=="LoadBalancer") | "\(.metadata.namespace) \(.metadata.name)"' |
    while read -r ns n; do kubectl -n "$ns" delete svc "$n"; done
  # Deleting the NodePool makes Karpenter terminate every node it launched.
  kubectl delete nodepool --all --ignore-not-found
  echo "Waiting for Karpenter nodes to terminate..."
  for _ in $(seq 1 30); do
    left=$(kubectl get nodeclaims --no-headers 2>/dev/null | wc -l)
    [[ "$left" -eq 0 ]] && break
    echo "  $left nodeclaim(s) remaining"; sleep 10
  done
fi

echo "== 2. terraform destroy =="
terraform destroy -auto-approve || { echo "Retrying destroy once..."; sleep 30; terraform destroy -auto-approve; }

echo "== 3. Orphan checks ($REGION) =="
FAIL=0
check () {  # $1 label, $2 command that prints IDs (empty = clean)
  local out; out=$(eval "$2" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/^ //;s/ $//')
  if [[ -z "$out" || "$out" == "None" ]]; then printf "  [OK]   %-32s none\n" "$1"
  else printf "  [FAIL] %-32s %s\n" "$1" "$out"; FAIL=1; fi
}
check "EKS clusters"                "$AWS eks list-clusters --query 'clusters[?@==\`$NAME\`]' --output text"
check "EC2 instances (project)"     "$AWS ec2 describe-instances --filters Name=tag:eks:eks-cluster-name,Values=$NAME Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text"
check "NAT Gateways"                "$AWS ec2 describe-nat-gateways --filter Name=state,Values=pending,available --query 'NatGateways[].NatGatewayId' --output text"
check "Elastic IPs (unassociated)"  "$AWS ec2 describe-addresses --query 'Addresses[?AssociationId==null].AllocationId' --output text"
check "Load Balancers (ALB/NLB)"    "$AWS elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerArn' --output text"
check "Classic Load Balancers"      "$AWS elb describe-load-balancers --query 'LoadBalancerDescriptions[].LoadBalancerName' --output text"
check "EBS volumes (unattached)"    "$AWS ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId' --output text"
check "VPCs (project tag)"          "$AWS ec2 describe-vpcs --filters Name=tag:Project,Values=$NAME --query 'Vpcs[].VpcId' --output text"
check "SQS interruption queue"      "$AWS sqs list-queues --queue-name-prefix $NAME --query 'QueueUrls' --output text"
check "EKS log group"               "$AWS logs describe-log-groups --log-group-name-prefix /aws/eks/$NAME --query 'logGroups[].logGroupName' --output text"

echo
if [[ $FAIL -eq 0 ]]; then
  echo "Status: Destroyed & Clean"
else
  echo "Status: ORPHANS FOUND - review the [FAIL] lines above (some may predate this project)."
  exit 1
fi
