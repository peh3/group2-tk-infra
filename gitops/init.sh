#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="group2-tk-cluster"
AWS_REGION="ap-southeast-1"

echo "=== 1. Updating Kubeconfig ==="
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

echo "=== 2. Applying Base StorageClass (gp3) ==="
kubectl apply -f bootstrap/common-infra/gp3/gp3.yaml

echo "=== 3. Installing Argo CD ==="
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values bootstrap/common-infra/argocd/argocd-values.yaml \
  --wait

echo "Waiting for Argo CD server..."
kubectl wait --namespace argocd \
  --for=condition=Available deployment/argocd-server \
  --timeout=120s

echo "=== Applying Argo CD AppProjects ==="
kubectl apply -f infra/projects/infra-project.yaml
kubectl apply -f sre/projects/sre-project.yaml
kubectl apply -f app/projects/app-project.yaml

echo "=== Deploying Root Applications (GitOps Handoff) ==="
kubectl apply -f bootstrap/root-infra.yaml
kubectl apply -f bootstrap/root-sre.yaml
kubectl apply -f bootstrap/root-app.yaml

echo ""
echo "============================================================"
echo "          Argo CD Bootstrapped Successfully                 "
echo "============================================================"
echo -n "Argo CD Initial Password: "
kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""
echo "============================================================"