#!/usr/bin/env bash
set -eo pipefail

CLUSTER_NAME="group2-tk-cluster"
AWS_REGION="ap-southeast-1"

echo "=========================================="
echo " Starting Full GitOps & Infra Teardown"
echo " Cluster: ${CLUSTER_NAME} (${AWS_REGION})"
echo "=========================================="

# 1. Update Kubeconfig
echo "--> [1/10] Ensuring cluster access..."
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

# Helper function to remove finalizers cleanly on both macOS (BSD) and Linux (GNU)
remove_finalizers() {
  local kind=$1
  local ns=$2
  local ns_arg=""
  [ -n "${ns}" ] && ns_arg="-n ${ns}"

  for item in $(kubectl get "${kind}" ${ns_arg} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    echo "Stripping finalizers from ${kind}/${item} in namespace '${ns:-cluster-wide}'..."
    kubectl patch "${kind}" "${item}" ${ns_arg} --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
  done
}

# 2. Delete Argo CD Applications & Projects
echo "--> [2/10] Deleting Argo CD Applications and AppProjects..."
if kubectl get crd applications.argoproj.io >/dev/null 2>&1; then
  remove_finalizers "applications.argoproj.io" "argocd"
  kubectl delete applications.argoproj.io --all -n argocd --cascade=foreground --timeout=45s 2>/dev/null || true
  remove_finalizers "applications.argoproj.io" "argocd"
fi

if kubectl get crd appprojects.argoproj.io >/dev/null 2>&1; then
  remove_finalizers "appprojects.argoproj.io" "argocd"
  kubectl delete appprojects.argoproj.io --all -n argocd --timeout=30s 2>/dev/null || true
  remove_finalizers "appprojects.argoproj.io" "argocd"
fi

# 3. Clean Ingresses and LoadBalancer Services (Wait for AWS NLB tear down)
echo "--> [3/10] Removing Ingresses and LoadBalancer Services..."
kubectl delete ingress --all --all-namespaces --timeout=45s 2>/dev/null || true

# Explicitly delete the ingress-nginx LoadBalancer service to trigger AWS NLB deletion
if kubectl get svc ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1; then
  echo "Deleting ingress-nginx LoadBalancer service..."
  kubectl delete svc ingress-nginx-controller -n ingress-nginx --timeout=60s || true
fi

# Delete all remaining services across platform namespaces
for ns in ingress-nginx monitoring argocd; do
  kubectl delete svc --all -n "${ns}" --timeout=30s 2>/dev/null || true
done

echo "Waiting for AWS Network Load Balancers to release..."
sleep 20

# 4. Uninstall Helm Releases
echo "--> [4/10] Uninstalling Helm releases..."
helm list -A -q | while read -r release; do
  ns=$(helm list -A --filter "^${release}$" -o json | jq -r '.[0].namespace' 2>/dev/null)
  if [ -n "${ns}" ] && [ "${ns}" != "null" ]; then
    echo "Uninstalling helm release '${release}' in namespace '${ns}'..."
    helm uninstall "${release}" -n "${ns}" 2>/dev/null || true
  fi
done

# 5. Remove cert-manager and ACME Resources
echo "--> [5/10] Cleaning Cert-Manager and ACME resources..."
if kubectl get crd clusterissuers.cert-manager.io >/dev/null 2>&1; then
  remove_finalizers "clusterissuers.cert-manager.io" ""
  kubectl delete clusterissuer --all --timeout=30s 2>/dev/null || true
fi
if kubectl get crd certificates.cert-manager.io >/dev/null 2>&1; then
  remove_finalizers "certificates.cert-manager.io" ""
  kubectl delete certificate --all --all-namespaces --timeout=30s 2>/dev/null || true
fi
if kubectl get crd challenges.acme.cert-manager.io >/dev/null 2>&1; then
  remove_finalizers "challenges.acme.cert-manager.io" ""
  kubectl delete challenge --all --all-namespaces --timeout=30s 2>/dev/null || true
fi

# 6. Delete Cluster-Scoped Webhook Configurations (Prevents blocking new installs)
echo "--> [6/10] Removing validating/mutating webhook configurations..."
kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/instance=ingress-nginx 2>/dev/null || true
kubectl delete validatingwebhookconfigurations -l app.kubernetes.io/instance=cert-manager 2>/dev/null || true
kubectl delete mutatingwebhookconfigurations -l app.kubernetes.io/instance=cert-manager 2>/dev/null || true

# 7. Delete Stuck Namespaces and Force Finalize
echo "--> [7/10] Deleting namespaces..."
NAMESPACES_TO_DELETE=(retail-store monitoring cert-manager external-dns ingress-nginx argocd)

for ns in "${NAMESPACES_TO_DELETE[@]}"; do
  if kubectl get ns "${ns}" >/dev/null 2>&1; then
    echo "Deleting namespace: ${ns}..."
    kubectl delete ns "${ns}" --timeout=30s 2>/dev/null || true

    # If still present or Terminating, strip finalizers via JSON API
    if kubectl get ns "${ns}" >/dev/null 2>&1; then
      echo "Namespace ${ns} is lingering. Wiping finalizers directly via API..."
      kubectl get ns "${ns}" -o json 2>/dev/null \
        | jq '.spec.finalizers = []' \
        | kubectl replace --raw "/api/v1/namespaces/${ns}/finalize" -f - 2>/dev/null || true
    fi
  fi
done

# 8. Remove CRDs
echo "--> [8/10] Removing Custom Resource Definitions (CRDs)..."
kubectl get crd -o name 2>/dev/null | grep -E "coreos.com|cert-manager.io|argoproj.io|externaldns.k8s.io" | while read -r crd; do
  echo "Deleting CRD: ${crd}..."
  kubectl patch "${crd}" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  kubectl delete "${crd}" --timeout=20s 2>/dev/null || true
done

# 9. Clean Lingering ClusterRoles / ClusterRoleBindings
echo "--> [9/10] Removing leftover cluster roles and bindings..."
for pattern in argocd cert-manager ingress-nginx external-dns prometheus; do
  kubectl get clusterrole -o name 2>/dev/null | grep "${pattern}" | xargs -n1 kubectl delete 2>/dev/null || true
  kubectl get clusterrolebinding -o name 2>/dev/null | grep "${pattern}" | xargs -n1 kubectl delete 2>/dev/null || true
done

# 10. Verify Clean Cluster State
echo "--> [10/10] Verifying cluster baseline..."
echo "--- Active Namespaces ---"
kubectl get ns
echo "--- LoadBalancer Services ---"
kubectl get svc -A --field-selector spec.type=LoadBalancer

echo "=========================================="
echo " Cluster clean! Ready for fresh bootstrap."
echo " Run ./init.sh to rebuild the platform."
echo "=========================================="