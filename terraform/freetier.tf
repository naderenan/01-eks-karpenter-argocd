################################################################################
# AWS Free plan support. Free-plan accounts can only launch "free-tier eligible"
# instance types (RunInstances fails with InvalidParameterCombination otherwise).
# Ask AWS which types this account may use, and only ever pick from that list.
################################################################################
data "aws_ec2_instance_types" "free_tier" {
  filter {
    name   = "free-tier-eligible"
    values = ["true"]
  }
}

locals {
  free_tier_types = data.aws_ec2_instance_types.free_tier.instance_types

  # Use the requested system node type when the account allows it; otherwise the
  # roomiest eligible x86 type available, falling back to t3.small.
  system_type_preference = [var.system_node_instance_type, "m7i-flex.large", "c7i-flex.large", "t3.small"]
  system_node_type = [
    for t in local.system_type_preference : t
    if !var.free_plan_account || contains(local.free_tier_types, t)
  ][0]

  # t3.small only fits 11 pods per node with the VPC CNI, so run 3 of them.
  system_node_count = local.system_node_type == "t3.small" ? 3 : 2
}

locals {
  karpenter_requirements = concat(
    [{ key = "kubernetes.io/arch", operator = "In", values = ["amd64", "arm64"] }],
    var.free_plan_account ? [
      # Free plan: only free-tier eligible types, On-Demand only.
      { key = "node.kubernetes.io/instance-type", operator = "In", values = local.free_tier_types },
      { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
    ] : [
      { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot", "on-demand"] }, # Spot preferred
      { key = "karpenter.k8s.aws/instance-category", operator = "In", values = ["c", "m", "r", "t"] },
      { key = "karpenter.k8s.aws/instance-generation", operator = "Gt", values = ["4"] },
      { key = "karpenter.k8s.aws/instance-size", operator = "NotIn", values = ["metal", "24xlarge", "32xlarge", "48xlarge"] },
    ]
  )
}
