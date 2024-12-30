resource "helm_release" "argocd" {
  depends_on       = [kind_cluster.k8s]
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "3.35.4"
  values           = [file("values.yaml")]
}

