## Accessing Platform Dashboards

After successfully running `./init.sh`, the core platform UI dashboards will be provisioned. Use the commands below to retrieve your initial admin passwords.

### 1. Argo CD
Argo CD orchestrates our GitOps deployments and provides a UI to monitor application health and sync status.

* **URL:** [https://group2-tk-argocd.sctp-sandbox.com](https://group2-tk-argocd.sctp-sandbox.com)
* **Username:** `admin`
* **Retrieve Password:**
  Run the following command to decode the initial admin password from the Kubernetes secret:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo


### 2. Grafana (Prometheus Monitoring Stack)
Grafana provides cluster observability, metrics, and alerting dashboards, deployed via the kube-prometheus-stack.

* **URL:** [https://group2-tk-grafana.sctp-sandbox.com](https://group2-tk-grafana.sctp-sandbox.com)
* **Username:** `admin`
* **Retrieve Password:**
  Run the following command to decode the initial admin password from the Kubernetes secret:
  ```bash
  kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d && echo


### 3. Import Component Dashboards in Grafana
The kube-prometheus-stack comes pre-loaded with dashboards for Kubernetes core metrics (CPU, memory, networking), but it does not include dashboards for third-party apps by default. You need to import community dashboards into Grafana to see your infrastructure metrics:

* NGINX Ingress Controller: Import Dashboard ID 9614
* Argo CD: Import Dashboard ID 14191
* Cert-Manager: Import Dashboard ID 11001
(To import: Go to Grafana UI -> Dashboards -> Import -> Paste the ID -> Select your Prometheus datasource).


---
# SOP: OpenTelemetry Webhook x509 Certificate Mismatch

## Overview
This SOP details the resolution for a recurring race condition between `cert-manager`, Argo CD, and the `opentelemetry-operator`. 

### Symptom
Argo CD reports an `OutOfSync` or `SyncFailed` status for `OpenTelemetryCollector` or `Instrumentation` resources. The Argo CD UI or controller logs display the following error:
> `tls: failed to verify certificate: x509: certificate signed by unknown authority (possibly because of "crypto/rsa: verification error" while trying to verify candidate authority certificate "opentelemetry-operator-operator-ca")`

### Root Cause
A "split-brain" certificate mismatch involving cluster-scoped resources. 
If `cert-manager` is uninstalled, upgraded, or its pods cycle, the previous Certificate Authority (CA) bundle is invalidated. However, the `MutatingWebhookConfiguration` and `ValidatingWebhookConfiguration` for OpenTelemetry are **cluster-scoped** and retain the dead `caBundle` string. When the API Server attempts to validate new OpenTelemetry manifests, it checks the Operator's fresh TLS certificate against the stale CA bundle in the webhook configuration, resulting in a rejected connection.

---

## Resolution Steps

### 1. Identify the Stale Webhooks
List the cluster-scoped webhooks belonging to the OpenTelemetry Operator:
```bash
kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations | grep opentelemetry