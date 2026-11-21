################################################################################
# ArgoCD (GitOps controller)
# Exposed as ClusterIP only - reach the UI with `kubectl port-forward`,
# so no public load balancer is created.
################################################################################
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  wait             = true
  timeout          = 900

  values = [yamlencode({
    global = {
      nodeSelector = {
        workload = "system"
      }
    }
    configs = {
      params = {
        "server.insecure" = true # TLS is terminated by port-forward / a future ingress
      }
    }
    server = {
      service = {
        type = "ClusterIP"
      }
    }
    dex = {
      enabled = false
    }
  })]

  depends_on = [module.eks]
}

################################################################################
# Demo GitOps application - ArgoCD keeps it in sync with Git automatically.
################################################################################
resource "kubectl_manifest" "guestbook_app" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: guestbook
      namespace: argocd
      finalizers:
        - resources-finalizer.argocd.argoproj.io
    spec:
      project: default
      source:
        repoURL: ${var.gitops_repo_url}
        targetRevision: HEAD
        path: ${var.gitops_repo_path}
      destination:
        server: https://kubernetes.default.svc
        namespace: guestbook
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
  YAML

  depends_on = [helm_release.argocd, kubectl_manifest.karpenter_node_pool]
}
