#!/usr/bin/env bash
set -euo pipefail

echo "=== 1. Updating Kubeconfig ==="
aws eks update-kubeconfig --region ap-southeast-1 --name group2-tk-cluster

echo "=== 2. Adding & Updating Helm Repositories ==="
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo add jetstack https://charts.jetstack.io
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "=== 3. Applying StorageClass (gp3) ==="
# Ensure gp3 StorageClass exists prior to PVC allocation
kubectl apply -f bootstrap/common-infra/gp3/gp3.yaml

echo "=== 4. Deploying Ingress-NGINX Controller ==="
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values bootstrap/common-infra/ingress-nginx/ingress-nginx-values.yaml \
  --wait

echo "=== 5. Deploying ExternalDNS ==="
helm upgrade --install external-dns external-dns/external-dns \
  --namespace external-dns \
  --create-namespace \
  --values bootstrap/common-infra/external-dns/external-dns-values.yaml \
  --wait

echo "=== 6. Deploying cert-manager ==="
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --values bootstrap/common-infra/cert-manager/cert-manager-values.yaml \
  --wait

echo "Waiting for cert-manager webhook to become available..."
kubectl wait --namespace cert-manager \
  --for=condition=Available deployment/cert-manager-webhook \
  --timeout=60s

echo "Applying ClusterIssuer..."
kubectl apply -f bootstrap/common-infra/cert-manager/cluster-issuer.yaml

echo "=== 7. Deploying Argo CD ==="
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values bootstrap/common-infra/argocd/argocd-values.yaml \
  --wait

echo "Waiting for Argo CD server deployment..."
kubectl wait --namespace argocd \
  --for=condition=Available deployment/argocd-server \
  --timeout=120s

echo "=== 8. Applying Argo CD AppProjects (RBAC Boundaries) ==="
kubectl apply -f sre/projects/sre-project.yaml
kubectl apply -f app/projects/app-project.yaml

echo "=== 9. Handing Off to GitOps (Deploying Root Applications) ==="
# SRE root triggers kube-prometheus-stack and platform routing
kubectl apply -f bootstrap/root-sre.yaml

# App root triggers business and microservice workloads
kubectl apply -f bootstrap/root-app.yaml

echo ""
echo "============================================================"
echo "          Platform Bootstrap Complete                       "
echo "============================================================"
echo "Argo CD Web UI: https://group2-tk-argocd.sctp-sandbox.com"
echo "Argo CD Username: admin"
echo -n "Argo CD Initial Password: "
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""
echo "============================================================"
echo "All further deployments (Prometheus, Grafana, App workloads)"
echo "are now being reconciled automatically by Argo CD via Git."
echo "============================================================"