# Upwork Portfolio Card: Project 1

## Title (<= 70 chars)
Production AWS EKS with Karpenter Autoscaling & ArgoCD GitOps

## Role
AWS DevOps / Platform Engineer (design, Terraform build, security hardening, documentation)

## Project Description
PROBLEM: Fixed-size Kubernetes node groups were sitting 60% idle, took minutes to scale, and were deployed by hand with kubectl. There was no audit trail, and SSH plus IMDSv1 left security gaps.

SOLUTION: I built a production-style Amazon EKS 1.35 platform entirely in modular Terraform. It has a 3-AZ VPC with private worker nodes. Karpenter v1 provisions right-sized nodes in about 35 seconds (measured in the live run), Spot-first with On-Demand fallback, and consolidates idle capacity automatically. An SQS + EventBridge pipeline handles Spot interruptions gracefully. ArgoCD runs GitOps with automated sync, prune and self-heal, so Git is the single source of truth. Security includes no SSH (SSM Session Manager only), enforced IMDSv2, EKS Pod Identity and Access Entries, encrypted EBS, and audit logs in CloudWatch.

IMPACT: Scale-up time dropped from minutes to about 35 seconds. Spot-first scheduling plus consolidation typically cuts compute cost by 40–70% for bursty workloads. The whole environment deploys in about 20 minutes, and one script destroys it and audits the account for orphaned resources. Full code, architecture diagram and client report are on GitHub.

## Skills (8)
- Amazon EKS
- Kubernetes
- Terraform
- Karpenter
- Argo CD
- Amazon Web Services
- DevOps
- Helm

## Project URL
https://github.com/naderenan/01-eks-karpenter-argocd

## Media to upload (in order)
1. architecture.png
2. screenshots/01-eks-cluster-overview.png
3. screenshots/02-karpenter-scaling.png
4. screenshots/03-argocd-synced.png
5. screenshots/04-ec2-nodes.png
