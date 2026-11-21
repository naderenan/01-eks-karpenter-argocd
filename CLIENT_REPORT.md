# Client Report: Production EKS Platform with Karpenter & ArgoCD

**Engagement type:** Platform build (Infrastructure as Code)  **Stack:** AWS EKS 1.35, Terraform, Karpenter v1, ArgoCD, Helm

## 1. Problem
A growing engineering team was running Kubernetes on fixed-size node groups:
- **Over-provisioning.** Nodes sized for peak load sat 60–70% idle most of the day.
- **Slow scaling.** Cluster Autoscaler took 3–5 minutes to add capacity during traffic spikes.
- **Manual, drift-prone deployments.** Engineers ran `kubectl apply` by hand, with no audit trail of what was running.
- **Security gaps.** Nodes had public SSH keys, IMDSv1 was enabled, and long-lived IAM credentials were stored in pods.

## 2. Solution
A Terraform-defined EKS platform that a new engineer can stand up in about 20 minutes:
- **Network:** A 3-AZ VPC with worker nodes in private subnets only.
- **Karpenter autoscaling:** Karpenter launches the cheapest instance that fits pending pods, in about 60 seconds. It tries Spot first and falls back to On-Demand across amd64 and arm64 families. It consolidates under-used nodes automatically, and a hard CPU/memory ceiling caps spend.
- **Spot interruption handling:** An SQS queue fed by EventBridge drains workloads gracefully before AWS reclaims a Spot instance.
- **ArgoCD GitOps:** Git is the single source of truth. Every change is a reviewed commit, and drift is self-healed automatically.
- **Repeatable teardown:** One script drains, destroys and audits the account for orphaned resources.

## 3. Security
- **No SSH.** Node access goes through AWS Systems Manager Session Manager, with no port 22 open.
- **IMDSv2 enforced** with a hop limit of 1, so pods cannot steal node IAM credentials.
- **EKS Pod Identity** gives Karpenter short-lived, scoped credentials. No static keys exist.
- **EKS Access Entries** replace the fragile `aws-auth` ConfigMap.
- **Data and logging:** EBS volumes are encrypted. API, audit and authenticator logs ship to CloudWatch.
- **API endpoint** is restricted to an allow-listed CIDR. ArgoCD runs internal-only (ClusterIP).

## 4. Cost Impact
| | Before (fixed node groups) | After (Karpenter) |
|---|---|---|
| Compute pricing | 100% On-Demand | Spot-first (typically 60–90% cheaper per vCPU) |
| Idle capacity | ~60% | Consolidated within minutes |
| Scale-up time | 3–5 min | ~60 s |
| Est. compute saving | – | **40–70%** on bursty workloads |

The demo environment costs **about $0.24/hr** at baseline and can be destroyed to $0 with one command. Pinning EKS to a standard-support version avoids the 6x extended-support fee ($0.60/hr vs $0.10/hr).

## 5. Validation (live run)
- **Karpenter:** 3 pending pods produced 3 new nodes, Ready in ~35 seconds. Scaling to zero removed them within ~2 minutes (consolidation).
- **GitOps:** ArgoCD reported the guestbook application `Synced` / `Healthy` with automated prune and self-heal.
- **Security:** every node in private subnets, no public IP, IMDSv2 `required`. Access via SSM only.
- **Account constraints handled:** the target account was on the AWS Free plan, so the platform was adapted to launch only free-tier eligible instance types, discovered automatically from the EC2 API.
- **Teardown:** destroyed after the demo, then audited for leftover clusters, instances, NAT gateways and Elastic IPs.

*Savings figures are typical industry ranges for Spot plus consolidation, not measured client data.*
