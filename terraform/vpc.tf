data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = var.project_name
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project     = local.name
    Environment = "portfolio"
    ManagedBy   = "terraform"
    Repository  = "01-eks-karpenter-argocd"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name
  cidr = var.vpc_cidr
  azs  = local.azs

  # /20 private subnets leave plenty of pod IPs for the VPC CNI.
  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true # cost: one NAT instead of three (trade-off: AZ-level egress SPOF)
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter discovers which subnets to launch nodes into via this tag.
    "karpenter.sh/discovery" = local.name
  }
}
