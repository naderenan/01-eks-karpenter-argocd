# AUTOPILOT: runs the demo, saves every output for Claude, then waits for Claude's
# signals (GitHub repo URL / destroy). SAFETY: destroys everything automatically
# after 4 hours even if no signal arrives, so the bill can't run on.
$ErrorActionPreference = "Continue"
$env:AWS_PROFILE = "portfolio-sandbox"; $env:AWS_REGION = "us-east-1"
$env:GCM_INTERACTIVE = "never"; $env:GIT_TERMINAL_PROMPT = "0"
$root = Split-Path -Parent $PSScriptRoot
$flags = Join-Path $root ".autopilot"; $out = Join-Path $root "out"
New-Item -ItemType Directory -Force $flags, $out | Out-Null
$deadline = (Get-Date).AddHours(4)
function Status($s) { "$(Get-Date -Format s) $s" | Add-Content (Join-Path $flags "status.txt"); Write-Host "`n>>> $s" -ForegroundColor Cyan }
function Run($file, [string]$title, [scriptblock]$sb) {
  $f = Join-Path $out $file
  "`n$ $title" | Out-File -Append -Encoding utf8 $f
  & $sb 2>&1 | ForEach-Object { "$_" } | Tee-Object -Append -FilePath $f | Out-Host
}
Set-Location $root
Status "started"

# ---------- 1. Cluster overview ----------
Run "01-cluster.txt" "kubectl get nodes -o wide" { kubectl get nodes -o wide }
Run "01-cluster.txt" "kubectl get pods -A" { kubectl get pods -A }
Run "01-cluster.txt" "aws eks describe-cluster (summary)" { aws eks describe-cluster --name eks-karpenter-argocd --query "cluster.{name:name,version:version,status:status,platform:platformVersion,auth:accessConfig.authenticationMode,logging:logging.clusterLogging[0].types}" --output table }

# ---------- 2. Karpenter scale-out ----------
kubectl apply -f k8s/inflate.yaml | Out-Host
kubectl scale deployment inflate --replicas=3 | Out-Host
Status "scaling inflate to 3 replicas, waiting for Karpenter nodes"
for ($i=0; $i -lt 30; $i++) {
  $pending = kubectl get pods -l app=inflate --field-selector=status.phase!=Running -o name 2>$null
  if (-not $pending) { break }; Start-Sleep 15
}
Run "02-karpenter.txt" "kubectl get nodeclaims -o wide" { kubectl get nodeclaims -o wide }
Run "02-karpenter.txt" "kubectl get nodes -L karpenter.sh/nodepool,node.kubernetes.io/instance-type,karpenter.sh/capacity-type,topology.kubernetes.io/zone" { kubectl get nodes -L karpenter.sh/nodepool,node.kubernetes.io/instance-type,karpenter.sh/capacity-type,topology.kubernetes.io/zone }
Run "02-karpenter.txt" "kubectl get pods -l app=inflate -o wide" { kubectl get pods -l app=inflate -o wide }
Run "02-karpenter.txt" "kubectl -n kube-system logs deploy/karpenter (launch events)" { kubectl -n kube-system logs deploy/karpenter --tail=400 | Select-String -Pattern "launched nodeclaim|registered nodeclaim|initialized nodeclaim|disrupting" | Select-Object -Last 12 }
Run "04-ec2.txt" "aws ec2 describe-instances (cluster nodes)" { aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=eks-karpenter-argocd" "Name=instance-state-name,Values=running,pending" --query "Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,Lifecycle:InstanceLifecycle,AZ:Placement.AvailabilityZone,PrivateIP:PrivateIpAddress,PublicIP:PublicIpAddress,IMDS:MetadataOptions.HttpTokens,ManagedBy:Tags[?Key=='karpenter.sh/nodepool']|[0].Value}" --output table }

# ---------- 3. ArgoCD ----------
for ($i=0; $i -lt 20; $i++) { $h = kubectl -n argocd get application guestbook -o jsonpath="{.status.health.status}" 2>$null; if ($h -eq "Healthy") { break }; Start-Sleep 15 }
Run "03-argocd.txt" "kubectl -n argocd get applications -o wide" { kubectl -n argocd get applications -o wide }
Run "03-argocd.txt" "kubectl -n guestbook get deploy,svc,pods" { kubectl -n guestbook get deploy,svc,pods }
Run "03-argocd.txt" "kubectl -n argocd get pods" { kubectl -n argocd get pods }

# ---------- 2b. Consolidation ----------
kubectl scale deployment inflate --replicas=0 | Out-Host
Status "scaled inflate to 0, waiting for consolidation"
for ($i=0; $i -lt 24; $i++) { $nc = kubectl get nodeclaims -o name 2>$null; if (-not $nc) { break }; Start-Sleep 15 }
Run "02b-consolidation.txt" "kubectl get nodeclaims (after scale to 0)" { kubectl get nodeclaims; "nodeclaims remaining: " + ((kubectl get nodeclaims -o name 2>$null | Measure-Object).Count) }
Run "02b-consolidation.txt" "kubectl get nodes" { kubectl get nodes -L karpenter.sh/nodepool }
Status "captured"

# ---------- 4. Wait for Claude's signals ----------
$destroyNow = $false
while (-not $destroyNow) {
  $g = Join-Path $flags "git-remote.txt"
  if (Test-Path $g) {
    $url = (Get-Content $g -Raw).Trim()
    Remove-Item $g -Force
    if ($url -match '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(\.git)?$') {
      Status "git push to $url"
      Run "git.txt" "git push" {
        if (-not (Test-Path .git)) { git init -b main }
        git add -A; git -c user.name="nader" commit -m "EKS + Karpenter + ArgoCD platform (Terraform)" ; git branch -M main
        git remote remove origin 2>$null; git remote add origin $url
        git push -u origin main
        "GIT_EXIT=$LASTEXITCODE"
      }
      Status "git done"
    } else { Status "git url rejected: $url" }
  }
  if (Test-Path (Join-Path $flags "recapture")) { Remove-Item (Join-Path $flags "recapture") -Force; Status "recapture requested (ignored: already captured)" }
  if (Test-Path (Join-Path $flags "destroy")) { $destroyNow = $true; Status "destroy signal received" }
  elseif ((Get-Date) -gt $deadline) { $destroyNow = $true; Status "4-hour safety deadline reached" }
  else { Start-Sleep 30 }
}

# ---------- 5. Destroy everything ----------
Status "destroying"
Run "destroy.txt" "remove Karpenter nodes first" {
  kubectl delete deployment inflate --ignore-not-found
  kubectl delete nodepool default --ignore-not-found --timeout=5m
  kubectl -n argocd patch application guestbook --type merge -p '{\"metadata\":{\"finalizers\":null}}' 2>$null
}
Start-Sleep 60
Set-Location (Join-Path $root "terraform")
Run "destroy.txt" "terraform destroy" { terraform destroy -auto-approve -input=false -no-color; "TF_EXIT=$LASTEXITCODE" }
if ((Get-Content (Join-Path $out "destroy.txt") -Raw) -notmatch "TF_EXIT=0") {
  Start-Sleep 90
  Run "destroy.txt" "terraform destroy (retry)" { terraform destroy -auto-approve -input=false -no-color; "TF_EXIT=$LASTEXITCODE" }
}
Run "destroy.txt" "audit: anything left?" {
  "EKS clusters: " + (aws eks list-clusters --query "clusters" --output text)
  "Instances:    " + (aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=eks-karpenter-argocd" "Name=instance-state-name,Values=pending,running,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output text)
  "NAT gateways: " + (aws ec2 describe-nat-gateways --filter "Name=state,Values=pending,available" --query "NatGateways[].NatGatewayId" --output text)
  "Elastic IPs:  " + (aws ec2 describe-addresses --query "Addresses[].PublicIp" --output text)
  "VPCs:         " + (aws ec2 describe-vpcs --filters "Name=tag:Name,Values=eks-karpenter-argocd" --query "Vpcs[].VpcId" --output text)
  "Load bal.:    " + (aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName" --output text)
  "SQS queues:   " + (aws sqs list-queues --queue-name-prefix Karpenter --query "QueueUrls" --output text)
}
Status "finished"
Write-Host "`nAUTOPILOT FINISHED. Everything for this project is destroyed." -ForegroundColor Green
