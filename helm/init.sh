#!/usr/bin/env bash
set -euo pipefail

echo "=== 1. Updating Kubeconfig ==="
aws eks update-kubeconfig --region ap-southeast-1 --name group2-tk-cluster

echo "=== 2. Adding & Updating Helm Repositories ==="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo add jetstack https://charts.jetstack.io
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "=== 3. Creating StorageClass (gp3) ==="
# Ensure gp3 StorageClass exists prior to any PVC requests
kubectl apply -f sre/prometheus/kube-prometheus-gp3.yaml

echo "=== 4. Deploying Ingress-NGINX Controller ==="
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values common-infra/ingress-nginx/ingress-nginx-values.yaml \
  --wait

echo "=== 5. Deploying ExternalDNS ==="
helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --values common-infra/external-dns/external-dns-values.yaml \
  --wait

echo "=== 6. Deploying cert-manager ==="
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --values common-infra/cert-manager/cert-manager-values.yaml \
  --wait

echo "Waiting for cert-manager webhook to become available..."
kubectl wait --namespace cert-manager \
  --for=condition=Available deployment/cert-manager-webhook \
  --timeout=60s

echo "Applying ClusterIssuer..."
kubectl apply -f common-infra/cert-manager/cluster-issuer.yaml

echo "=== 7. Deploying kube-prometheus-stack ==="
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values sre/prometheus/kube-prometheus-stack-values.yaml \
  --timeout 15m \
  --wait

echo "=== 8. Enabling ServiceMonitors on Core Infrastructure ==="
# 1. Ingress-NGINX metrics
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --reuse-values \
  --set controller.metrics.enabled=true \
  --set controller.metrics.serviceMonitor.enabled=true

# 2. cert-manager metrics (applied declaratively to prevent chart schema validation errors)
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: cert-manager
  namespace: cert-manager
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: cert-manager
      app.kubernetes.io/instance: cert-manager
  endpoints:
    - port: tcp-prometheus-servicemonitor
      interval: 15s
EOF

# 3. ExternalDNS metrics
helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --reuse-values \
  --set serviceMonitor.enabled=true

echo "=== 9. Applying Prometheus & Grafana Ingresses ==="
kubectl apply -f sre/prometheus/prometheus-ingress.yaml
kubectl apply -f sre/prometheus/grafana-ingress.yaml

echo "=== 10. Deploying Argo CD ==="
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values common-infra/argocd/argocd-values.yaml \
  --wait

echo "Waiting for Argo CD initial admin secret..."
kubectl wait --namespace argocd \
  --for=condition=Available deployment/argocd-server \
  --timeout=120s

echo ""
echo "============================================================"
echo "          Platform Deployment Complete                      "
echo "============================================================"
echo "Grafana URL:    https://group2-tk-grafana.sctp-sandbox.com"
echo "Prometheus URL: https://group2-tk-prometheus.sctp-sandbox.com"
echo "Argo CD URL:    https://group2-tk-argocd.sctp-sandbox.com"
echo ""
echo "Argo CD Admin Username: admin"
echo -n "Argo CD Admin Password: "
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""
echo "============================================================"