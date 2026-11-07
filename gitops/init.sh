#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="group2-tk-cluster"
AWS_REGION="ap-southeast-1"
REPO_URL="https://github.com/peh3/group2-tk-infra.git"
AWS_SECRET_ID="group2-tk/argocd/github-pat"

echo "=========================================="
echo " Starting GitOps Cluster Bootstrap"
echo " Cluster: ${CLUSTER_NAME} (${AWS_REGION})"
echo "=========================================="

# 1. Update Kubeconfig
echo "--> [1/7] Updating kubeconfig..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# 2. Deploy default gp3 StorageClass
echo "--> [2/7] Applying AWS gp3 StorageClass..."
kubectl apply -f bootstrap/common-infra/gp3/gp3.yaml

# 3. Pre-install Prometheus Operator CRDs
# (Required to prevent Argo CD schema discovery validation errors before kube-prometheus-stack installs)
echo "--> [3/7] Applying Prometheus Operator CRDs via Server-Side Apply..."
kubectl apply --server-side \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml

# 4. Bootstrap Argo CD via Helm
echo "--> [4/7] Deploying Argo CD Helm chart..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values gitops/bootstrap/common-infra/argocd-values.yaml \
  --wait

echo "Waiting for Argo CD API server..."
kubectl wait --namespace argocd \
  --for=condition=Available deployment/argocd-server \
  --timeout=180s

# # 5. Fetch GitHub PAT from Secrets Manager and register private repo in Argo CD
# echo "--> [5/7] Registering Git repository authentication..."
# GITHUB_PAT=$(aws secretsmanager get-secret-value \
#   --secret-id "${AWS_SECRET_ID}" \
#   --region "${AWS_REGION}" \
#   --query SecretString --output text | jq -r .token)

# kubectl create secret generic repo-github-auth \
#   --namespace argocd \
#   --from-literal=type=git \
#   --from-literal=url="${REPO_URL}" \
#   --from-literal=username=git \
#   --from-literal=password="${GITHUB_PAT}" \
#   --dry-run=client -o yaml | kubectl apply -f -

# kubectl label secret repo-github-auth -n argocd \
#   argocd.argoproj.io/secret-type=repository --overwrite

# 6. Apply AppProjects (with destination argocd whitelisted)
echo "--> [6/7] Applying Argo CD AppProjects..."
kubectl apply -f infra/projects/infra-project.yaml
kubectl apply -f sre/projects/sre-project.yaml
kubectl apply -f app/projects/app-project.yaml

# 7. GitOps Handoff (App-of-Apps Root Deployments)
echo "--> [7/7] Applying Root GitOps Applications..."
kubectl apply -f bootstrap/root-infra.yaml
kubectl apply -f bootstrap/root-sre.yaml
kubectl apply -f bootstrap/root-app.yaml

echo "=========================================="
echo " GitOps bootstrap complete!"
echo " Argo CD is now orchestrating Infra, SRE, and Applications."
echo " Domain: https://group2-tk-argocd.sctp-sandbox.com"
echo "=========================================="