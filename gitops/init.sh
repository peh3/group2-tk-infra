#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="group2-tk-cluster"
AWS_REGION="ap-southeast-1"
REPO_URL="https://github.com/peh3/group2-tk-infra.git"
AWS_SECRET_ID="group2-tk/argocd/github-pat"
VALUES_FILE="bootstrap/common-infra/argocd-values.yaml"

echo "=========================================="
echo " Starting GitOps Cluster Bootstrap"
echo " Cluster: ${CLUSTER_NAME} (${AWS_REGION})"
echo "=========================================="

# 1. Update Kubeconfig
echo "--> [1/8] Updating kubeconfig..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# 2. Deploy default gp3 StorageClass
echo "--> [2/8] Applying AWS gp3 StorageClass..."
kubectl apply -f bootstrap/common-infra/gp3.yaml

# 3. Pre-install Prometheus Operator CRDs
# (Required to prevent Argo CD schema discovery validation errors before kube-prometheus-stack installs)
echo "--> [3/8] Applying Prometheus Operator CRDs via Server-Side Apply..."
kubectl apply --server-side \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheuses.yaml \
  -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.77.1/example/prometheus-operator-crd/monitoring.coreos.com_prometheusrules.yaml

# 4. Bootstrap Argo CD via Helm
echo "--> [4/8] Deploying Argo CD Helm chart with custom values..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values "${VALUES_FILE}" \
  --wait \
  --timeout 10m

echo "Waiting for Argo CD API server deployment rollout..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=180s

# 5. Apply AppProjects (with destination argocd whitelisted)
echo "--> [5/8] Applying Argo CD AppProjects..."
kubectl apply -f infra/projects/infra-project.yaml
kubectl apply -f sre/projects/sre-project.yaml
kubectl apply -f app/projects/app-project.yaml

# 6. GitOps Handoff (App-of-Apps Root Deployments)
echo "--> [6/8] Applying Root GitOps Applications..."
kubectl apply -f bootstrap/root-infra.yaml
kubectl apply -f bootstrap/root-sre.yaml
kubectl apply -f bootstrap/root-app.yaml

# 7. Dynamically Inject EKS API Host into Cilium Application
echo "--> [7/8] Resolving dynamic EKS endpoint and patching Cilium Application..."
EKS_ENDPOINT=$(aws eks describe-cluster \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}" \
  --query "cluster.endpoint" \
  --output text)

EKS_HOST=$(echo "${EKS_ENDPOINT}" | sed 's|https://||')
echo "    Resolved EKS Control Plane Host: ${EKS_HOST}"

# Wait briefly for root-infra to materialize the cilium application resource if needed
until kubectl get application cilium -n argocd >/dev/null 2>&1; do
  echo "    Waiting for Application 'cilium' to be registered by root-infra..."
  sleep 3
done

kubectl patch application cilium -n argocd --type=merge -p "{
  \"spec\": {
    \"source\": {
      \"helm\": {
        \"parameters\": [
          {
            \"name\": \"k8sServiceHost\",
            \"value\": \"${EKS_HOST}\"
          }
        ]
      }
    }
  }
}"
echo "    Successfully patched Cilium Application k8sServiceHost with ${EKS_HOST}."

# 8. Print Credentials and Access URL
echo "--> [8/8] Retrieving initial admin credentials..."
ADMIN_PWD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)

echo "=========================================="
echo " GitOps bootstrap complete!"
echo " Argo CD is now orchestrating Infra, SRE, and Applications."
echo " URL:      https://group2-tk-argocd.sctp-sandbox.com"
echo " Username: admin"
if [ -n "${ADMIN_PWD}" ]; then
  echo " Password: ${ADMIN_PWD}"
else
  echo " Password: (initial-admin-secret removed or password already changed)"
fi
echo "=========================================="