################################################################################
# 0. Dedicated Namespaces
################################################################################
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "loki" {
  metadata {
    name = "loki"
  }
  depends_on = [module.eks]
}

################################################################################
# 1. Metrics Server (Powers HPA & 'kubectl top')
################################################################################
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  namespace  = "kube-system"

  timeout         = 600
  cleanup_on_fail = true

  depends_on = [module.eks]

  # Comma is escaped with \\, to avoid Helm parser splitting errors
  set {
    name  = "args[0]"
    value = "--kubelet-preferred-address-types=InternalIP\\,ExternalIP\\,Hostname"
  }
}

################################################################################
# 2. cert-manager (Automated TLS via Let's Encrypt)
################################################################################
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.16.1"
  namespace        = "cert-manager"
  create_namespace = true

  timeout         = 900
  cleanup_on_fail = true

  depends_on = [module.eks]

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

################################################################################
# 3. Observability: kube-prometheus-stack (Prometheus + Grafana + Exporters)
################################################################################
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.5.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  timeout         = 900
  cleanup_on_fail = true

  depends_on = [
    module.eks,
    kubernetes_namespace.monitoring
  ]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = "AdminSecurePass2026!"
  }

  set {
    name  = "grafana.persistence.enabled"
    value = "true"
  }

  set {
    name  = "grafana.persistence.size"
    value = "10Gi"
  }

  set {
    name  = "grafana.additionalDataSources[0].name"
    value = "Loki"
  }

  set {
    name  = "grafana.additionalDataSources[0].type"
    value = "loki"
  }

  set {
    name  = "grafana.additionalDataSources[0].url"
    value = "http://loki.loki.svc.cluster.local:3100"
  }

  set {
    name  = "grafana.additionalDataSources[0].access"
    value = "proxy"
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "14d"
  }

  set {
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]"
    value = "ReadWriteOnce"
  }

  set {
    name  = "prometheus.prometheusSpec.