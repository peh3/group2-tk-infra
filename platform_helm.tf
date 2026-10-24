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
# 3. Observability: Single kube-prometheus-stack (Prometheus + Grafana + Exporters)
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

  # Grafana Administrator Credentials
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

  # Connect Loki as an integrated datasource in Grafana
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

  # Prometheus Single Server Configuration
  set {
    name  = "prometheus.prometheusSpec.replicas"
    value = "1"
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
    name  = "prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage"
    value = "20Gi"
  }
}

################################################################################
# 4. Observability: Loki (Centralized Log Store)
################################################################################
resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.24.0"
  namespace  = kubernetes_namespace.loki.metadata[0].name

  timeout         = 600
  cleanup_on_fail = true

  depends_on = [
    module.eks,[cite: 5]
    kubernetes_namespace.loki,
    aws_s3_bucket.loki_storage,
    aws_eks_pod_identity_association.loki
  ]

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"
      
      serviceAccount = {
        create = true
        name   = "loki"
      }

      loki = {
        auth_enabled = false
        commonConfig = {
          replication_factor = 1
        }
        
        # S3 Object Storage Configuration
        storage = {
          type = "s3"
          bucketNames = {
            chunks = aws_s3_bucket.loki_storage.id
            ruler  = aws_s3_bucket.loki_storage.id
            admin  = aws_s3_bucket.loki_storage.id
          }
          s3 = {
            region           = var.aws_region[cite: 10]
            insecure         = false
            s3ForcePathStyle = false
          }
        }

        # TSDB index schema
        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "s3"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }
      }

      singleBinary = {
        replicas = 1
        persistence = {
          enabled = false # Disables EBS PVC requirement; chunks ship directly to S3
        }
      }

      # Disable multi-component distributed deployments
      backend = {
        replicas = 0
      }
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }
      chunksCache = {
        allocatedMemory = 0
      }
      resultsCache = {
        allocatedMemory = 0
      }
    })
  ]
}

################################################################################
# 5. Observability: Promtail (Log Shipper DaemonSet)
################################################################################
resource "helm_release" "promtail" {
  name       = "promtail"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = "6.16.6"
  namespace  = kubernetes_namespace.loki.metadata[0].name

  timeout         = 600
  cleanup_on_fail = true

  depends_on = [
    module.eks,
    helm_release.loki
  ]

  set {
    name  = "config.clients[0].url"
    value = "http://loki.loki.svc.cluster.local:3100/loki/api/v1/push"
  }
}

################################################################################
# 6. ExternalDNS (Route 53 Sync for sctp-sandbox.com)
################################################################################
resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = "1.15.0"
  namespace        = "external-dns"
  create_namespace = true

  timeout         = 600
  cleanup_on_fail = true

  depends_on = [module.eks]

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "aws.zoneType"
    value = "public"
  }

  set {
    name  = "zoneIdFilters[0]"
    value = "Z00541411T1NGPV97B5C0"
  }

  set {
    name  = "domainFilters[0]"
    value = "sctp-sandbox.com"
  }

  set {
    name  = "sources[0]"
    value = "ingress"
  }

  set {
    name  = "sources[1]"
    value = "service"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "policy"
    value = "sync"
  }

  set {
    name  = "registry"
    value = "txt"
  }

  set {
    name  = "txtOwnerId"
    value = "${var.project_name}-cluster"
  }
}

################################################################################
# 7. Security: Kyverno (Policy Engine)
################################################################################
resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  version          = "3.3.4"
  namespace        = "kyverno"
  create_namespace = true

  timeout         = 600
  cleanup_on_fail = true

  depends_on = [module.eks]

  set {
    name  = "admissionController.replicas"
    value = "1"
  }
}

################################################################################
# 8. Security: Trivy Operator (Vulnerability Scanner)
################################################################################
resource "helm_release" "trivy_operator" {
  name             = "trivy-operator"
  repository       = "https://aquasecurity.github.io/helm-charts/"
  chart            = "trivy-operator"
  version          = "0.25.0"
  namespace        = "trivy-system"
  create_namespace = true

  timeout         = 600
  cleanup_on_fail = true

  depends_on = [module.eks]

  set {
    name  = "trivy.ignoreUnfixed"
    value = "true"
  }
}

################################################################################
# 9. Load Generator (Locust for Retail App Stress Testing)
################################################################################
resource "helm_release" "load_generator" {
  name             = "load-generator"
  repository       = "https://charts.deliveryhero.io/"
  chart            = "locust"
  version          = "0.31.5"
  namespace        = "loadtest"
  create_namespace = true

  timeout         = 600
  cleanup_on_fail = true

  depends_on = [module.eks]

  set {
    name  = "loadtest.locust_host"
    value = "http://ui.retail.svc.cluster.local:80"
  }

  set {
    name  = "master.replicas"
    value = "1"
  }

  set {
    name  = "worker.replicas"
    value = "2"
  }
}