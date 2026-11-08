## Accessing Platform Dashboards

After successfully running `./init.sh`, the core platform UI dashboards will be provisioned. Use the commands below to retrieve your initial admin passwords.

### 1. Argo CD
Argo CD orchestrates our GitOps deployments and provides a UI to monitor application health and sync status.

* **URL:** [https://group2-capstore-argocd.sctp-sandbox.com](https://group2-capstone-argocd.sctp-sandbox.com)
* **Username:** `admin`
* **Retrieve Password:**
  Run the following command to decode the initial admin password from the Kubernetes secret:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo


### 2. Grafana (Prometheus Monitoring Stack)
Grafana provides cluster observability, metrics, and alerting dashboards, deployed via the kube-prometheus-stack.

* **URL:** [https://group2-capstore-grafana.sctp-sandbox.com](https://group2-capstone-grafana.sctp-sandbox.com)
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