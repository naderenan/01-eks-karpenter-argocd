# Runs the whole deploy and writes everything to deploy-log.txt (Claude reads it to fix errors).
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$log  = Join-Path $root "deploy-log.txt"
$profile = "portfolio-sandbox"
Start-Transcript -Path $log -Force | Out-Null

function Step($name) { Write-Host "`n===== $name =====" -ForegroundColor Cyan }
function Stop-Here($msg) { Write-Host "`nSTOPPED: $msg" -ForegroundColor Red; Stop-Transcript | Out-Null; exit 1 }

Step "1. Tools"
foreach ($t in "terraform","aws","kubectl") {
  if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { Stop-Here "$t is not installed. Run in an Admin PowerShell: choco install terraform awscli kubernetes-cli -y  then reopen PowerShell." }
}
terraform -version; aws --version; kubectl version --client

Step "2. AWS credentials"
aws sts get-caller-identity --profile $profile
if ($LASTEXITCODE -ne 0) { Stop-Here "AWS profile '$profile' is not set up. Run ONLY this: aws configure --profile $profile   Then enter your Access Key, Secret Key, us-east-1, json. Then run this script again." }

Step "3. terraform init"
Set-Location (Join-Path $root "terraform")
terraform init -input=false -no-color
if ($LASTEXITCODE -ne 0) { Stop-Here "terraform init failed." }

Step "4. terraform validate"
terraform validate -no-color
if ($LASTEXITCODE -ne 0) { Stop-Here "terraform validate failed." }

# Stage A builds the network and cluster; the kubectl/helm providers need a real cluster endpoint first.
Step "5a. terraform apply, stage A: VPC + EKS + Karpenter IAM (about 15 minutes)"
terraform apply -auto-approve -input=false -no-color -target="module.vpc" -target="module.eks" -target="module.karpenter"
if ($LASTEXITCODE -ne 0) { Stop-Here "Stage A failed. Nothing is lost: tell Claude 'check' and run again after the fix." }

Step "5b. terraform apply, stage B: Karpenter, ArgoCD, demo app (about 5 minutes)"
terraform apply -auto-approve -input=false -no-color
if ($LASTEXITCODE -ne 0) { Stop-Here "Stage B failed. The cluster is up and billing: tell Claude 'check' and run again after the fix." }

Step "6. Cluster checks"
aws eks update-kubeconfig --name eks-karpenter-argocd --region us-east-1 --profile $profile
kubectl get nodes
kubectl get nodepools
kubectl -n argocd get applications

Write-Host "`nDONE. Tell Claude it finished." -ForegroundColor Green
Stop-Transcript | Out-Null
