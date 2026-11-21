# One destroy attempt. Attempts 1-2: clean terraform destroy.
# From attempt 3: also force-delete the billable resources directly with the AWS CLI.
param([int]$Attempt = 1)
$root = Split-Path -Parent $PSScriptRoot
kubectl delete nodepool default --ignore-not-found --timeout=3m 2>&1
Set-Location (Join-Path $root "terraform")
terraform destroy -auto-approve -input=false -no-color 2>&1
"TF_EXIT=$LASTEXITCODE"
if ($Attempt -ge 3) {
  "--- force cleanup with AWS CLI ---"
  $cl = "eks-karpenter-argocd"
  foreach ($ng in (aws eks list-nodegroups --cluster-name $cl --query "nodegroups[]" --output text 2>$null) -split "\s+") { if ($ng) { aws eks delete-nodegroup --cluster-name $cl --nodegroup-name $ng 2>&1 } }
  $ids = @()
  foreach ($tag in "tag:kubernetes.io/cluster/eks-karpenter-argocd","tag:eks:cluster-name") {
    $ids += (aws ec2 describe-instances --filters $(if ($tag -like "*kubernetes.io*") {"Name=$tag,Values=owned"} else {"Name=$tag,Values=$cl"}) "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text 2>$null) -split "\s+" | Where-Object { $_ } }
  if ($ids) { aws ec2 terminate-instances --instance-ids $ids 2>&1 }
  foreach ($nat in (aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=$cl*" "Name=state,Values=pending,available" --query "NatGateways[].NatGatewayId" --output text 2>$null) -split "\s+") { if ($nat) { aws ec2 delete-nat-gateway --nat-gateway-id $nat 2>&1 } }
  Start-Sleep 120
  foreach ($a in (aws ec2 describe-addresses --filters "Name=tag:Name,Values=$cl*" --query "Addresses[].AllocationId" --output text 2>$null) -split "\s+") { if ($a) { aws ec2 release-address --allocation-id $a 2>&1 } }
  # cluster can only go once its node groups are gone
  for ($k=0; $k -lt 20; $k++) { $left = aws eks list-nodegroups --cluster-name $cl --query "length(nodegroups)" --output text 2>$null; if (-not $left -or $left -eq "0") { break }; Start-Sleep 30 }
  aws eks delete-cluster --name $cl 2>&1
}
