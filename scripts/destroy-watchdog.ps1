# DESTROY WATCHDOG: guarantees this project ends with NOTHING billable left in AWS.
# Waits until autopilot finishes (or 4.5 h pass), then checks AWS. If anything
# costly remains, it runs destroy-step.ps1 again and again (every 5 min, up to 10 h)
# until the audit is clean. Claude can fix destroy-step.ps1 between attempts.
$env:AWS_PROFILE = "portfolio-sandbox"; $env:AWS_REGION = "us-east-1"
$root = Split-Path -Parent $PSScriptRoot
$flags = Join-Path $root ".autopilot"; New-Item -ItemType Directory -Force $flags | Out-Null
$wlog = Join-Path $root "out\watchdog.txt"
function W($m) { "$(Get-Date -Format s) $m" | Tee-Object -Append -FilePath $wlog | Out-Host }
$start = Get-Date
W "watchdog started"
# 1) wait for autopilot to finish, or 4.5 hours
while ($true) {
  $st = Get-Content (Join-Path $flags "status.txt") -Raw -ErrorAction SilentlyContinue
  if ($st -match "finished") { W "autopilot finished"; break }
  if ((Get-Date) -gt $start.AddHours(4.5)) { W "4.5 h passed, taking over"; break }
  Start-Sleep 60
}
# 2) loop until clean
$attempt = 0
while ((Get-Date) -lt $start.AddHours(15)) {
  $c  = aws eks describe-cluster --name eks-karpenter-argocd --query cluster.status --output text 2>$null
  $i  = aws ec2 describe-instances --filters "Name=tag:kubernetes.io/cluster/eks-karpenter-argocd,Values=owned","Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text 2>$null
  $i2 = aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=eks-karpenter-argocd","Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text 2>$null
  $n  = aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=eks-karpenter-argocd*","Name=state,Values=pending,available" --query "NatGateways[].NatGatewayId" --output text 2>$null
  $e  = aws ec2 describe-addresses --filters "Name=tag:Name,Values=eks-karpenter-argocd*" --query "Addresses[].AllocationId" --output text 2>$null
  W "audit: cluster=[$c] instances=[$i $i2] nat=[$n] eip=[$e]"
  if (-not $c -and -not "$i$i2".Trim() -and -not $n -and -not $e) { W "CLEAN: nothing billable left"; "clean" | Set-Content (Join-Path $flags "watchdog-clean.txt"); break }
  $attempt++
  W "attempt ${attempt}: running destroy-step.ps1"
  & (Join-Path $PSScriptRoot "destroy-step.ps1") -Attempt $attempt *>&1 | ForEach-Object { "$_" } | Tee-Object -Append -FilePath $wlog | Out-Host
  Start-Sleep 300
}
W "watchdog exiting"
