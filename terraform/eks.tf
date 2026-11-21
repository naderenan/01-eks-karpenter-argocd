module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = local.name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = var.public_access_cidrs

  # Whoever runs `terraform apply` gets cluster-admin via an EKS access entry (no aws-auth ConfigMap).
  enable_cluster_creator_admin_permissions = true

  # Control-plane logs for audit / troubleshooting.
  enabled_log_types = ["api", "audit", "authenticator"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    coredns = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  # Small, fixed "system" node group. Everything else is provisioned by Karpenter.
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [local.system_node_type]

      min_size     = local.system_node_count
      max_size     = 3
      desired_size = local.system_node_count

      labels = {
        "karpenter.sh/controller" = "true"
        "workload"                = "system"
      }

      # Nodes are reachable through SSM Session Manager - no SSH keys, no port 22.
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  node_security_group_tags = {
    # Karpenter attaches this security group to the nodes it launches.
    "karpenter.sh/discovery" = local.name
  }
}
