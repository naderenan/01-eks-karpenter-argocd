################################################################################
# Karpenter AWS side: controller IAM (Pod Identity), node IAM role,
# SQS interruption queue + EventBridge rules for Spot interruption handling.
################################################################################
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true

  # The controller policy is larger than the 6,144-char managed-policy quota,
  # so attach it inline on the role (10,240-char limit) instead.
  enable_inline_policy = true

  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${local.name}-karpenter-node"

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

################################################################################
# Karpenter controller (Helm)
################################################################################
resource "helm_release" "karpenter" {
  name                = "karpenter"
  namespace           = "kube-system"
  # Public ECR allows anonymous pulls. No registry login, so Helm never touches
  # the Windows credential store ("The stub received bad data").
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = var.karpenter_version
  wait                = true

  values = [yamlencode({
    nodeSelector = {
      "karpenter.sh/controller" = "true"
    }
    dnsPolicy = "Default"
    serviceAccount = {
      name = module.karpenter.service_account
    }
    settings = {
      clusterName       = module.eks.cluster_name
      clusterEndpoint   = module.eks.cluster_endpoint
      interruptionQueue = module.karpenter.queue_name
    }
    webhook = {
      enabled = false
    }
  })]

  depends_on = [module.eks]
}

################################################################################
# Karpenter Kubernetes side: EC2NodeClass + NodePool
################################################################################
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      role: ${module.karpenter.node_iam_role_name}
      amiSelectorTerms:
        - alias: al2023@latest
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      metadataOptions:
        httpTokens: required          # IMDSv2 only
        httpPutResponseHopLimit: 1    # pods cannot reach node credentials
      blockDeviceMappings:
        - deviceName: /dev/xvda
          ebs:
            volumeSize: 20Gi
            volumeType: gp3
            encrypted: true
            deleteOnTermination: true
      tags:
        Project: ${local.name}
        ManagedBy: karpenter
  YAML

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            group: karpenter.k8s.aws
            kind: EC2NodeClass
            name: default
          expireAfter: 168h           # rotate nodes weekly for patching
          requirements: ${jsonencode(local.karpenter_requirements)}
      limits:
        cpu: "32"                     # hard ceiling = cost guardrail
        memory: 128Gi
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
  YAML

  depends_on = [kubectl_manifest.karpenter_node_class]
}
