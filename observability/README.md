# Observability Stack

Two destinations, split by where the signal originates:

- **Self-hosted LGTM** (Loki + Grafana + Tempo + Mimir/Prometheus) with an OpenTelemetry Collector
  DaemonSet, for **app-level** signals. Runs in the `observability` namespace on the GKE Autopilot cluster.
- **Grafana Cloud**, for **infrastructure and billing** signals the in-cluster Collector can't see —
  fed by Grafana Alloy and the billing-exporter CronJob.

**Signals collected:**

| Signal  | How                                                          | Backend       |
|---------|-------------------------------------------------------------|---------------|
| Traces  | App → OTel SDK → Collector OTLP → Tempo                      | self-hosted   |
| Metrics | App → OTel SDK → Collector OTLP → Prometheus scrape endpoint | self-hosted   |
| Logs    | App → OTel SDK → Collector OTLP → Loki                       | self-hosted   |
| GCP infra metrics | Cloud Monitoring → Alloy → `remote_write`          | Grafana Cloud |
| GCP billing | BigQuery → billing-exporter CronJob → OTLP               | Grafana Cloud |

GCP infra metrics come from Grafana Alloy (`observability/alloy/`), which scrapes Cloud Monitoring
(ALB, Pub/Sub, GKE, Artifact Registry) and `remote_write`s to Grafana Cloud Prometheus. GCP billing
comes from the billing-exporter CronJob (`k8s/billing-exporter/`), which queries BigQuery and pushes
cost metrics to Grafana Cloud via OTLP.

> **GKE Autopilot note:** `hostPath` volumes and `hostNetwork` are blocked by Autopilot's workload
> isolation policy, so the OTel `filelog` receiver (stdout tailing) cannot be used. All app signals
> flow through the OTel SDK instead. Stdout logs from uninstrumented containers are not captured.

---

## Prerequisites

```bash
# Helm repos (one-time)
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

---

## Install order

### 1. Namespace

```bash
kubectl apply -f observability/namespace.yaml
```

### 2. Grafana admin secret

Copy the example and set a real password before applying:

```bash
cp observability/lgtm/grafana-secret.yaml.example observability/lgtm/grafana-secret.yaml
# Edit grafana-secret.yaml — change admin-password
kubectl apply -f observability/lgtm/grafana-secret.yaml
```

Do not commit `grafana-secret.yaml` (it is gitignored via the `.example` pattern).

### 3. OTel Collector

```bash
kubectl apply -f observability/collector/rbac.yaml
kubectl apply -f observability/collector/config.yaml
kubectl apply -f observability/collector/daemonset.yaml
kubectl apply -f observability/collector/cluster-collector.yaml
```

### 4. LGTM stack (Helm)

```bash
helm upgrade --install loki grafana/loki \
  -n observability -f observability/lgtm/loki-values.yaml

helm upgrade --install tempo grafana/tempo \
  -n observability -f observability/lgtm/tempo-values.yaml

helm upgrade --install prometheus prometheus-community/prometheus \
  -n observability -f observability/lgtm/prometheus-values.yaml

helm upgrade --install grafana grafana/grafana \
  -n observability -f observability/lgtm/grafana-values.yaml
```

### 5. Grafana HTTPRoute

Ensure the shared Gateway is running first (see `k8s/infra/README.md`).

```bash
kubectl apply -f observability/lgtm/grafana-httproute.yaml
```

DNS should point `observability.drolet.cloud` at the shared Gateway's IP:

```bash
kubectl get gateway shared-gateway -n infra
# Copy the ADDRESS value and add/update an A record in your DNS provider
```

TLS is handled by the wildcard cert in the shared Certificate Manager cert map.

### 6. Grafana Alloy (GCP infra metrics → Grafana Cloud)

Create the Grafana Cloud Prometheus credentials secret, then install Alloy via Helm:

```bash
cp observability/alloy/secret.yaml.example observability/alloy/secret.yaml
# Edit secret.yaml — set Grafana Cloud Prometheus url / username / password
kubectl apply -f observability/alloy/secret.yaml

kubectl apply -f observability/alloy/configmap.yaml
helm upgrade --install alloy grafana/alloy \
  -n observability -f observability/alloy/values.yaml
```

The billing-exporter CronJob is deployed separately from `k8s/billing-exporter/` and pushes to
Grafana Cloud via OTLP (secret `grafana-cloud-otlp` in the `apps` namespace).

---

## Accessing Grafana

### Public URL (after DNS + cert)

```
https://observability.drolet.cloud
```

### Port-forward (immediate, no DNS needed)

```bash
kubectl port-forward svc/grafana 3000:80 -n observability
# Open http://localhost:3000
```

### Default credentials

| Field    | Default value |
|----------|---------------|
| Username | `admin`       |
| Password | Whatever you set in `grafana-secret.yaml` |

To change the password after install:

```bash
kubectl create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password=<new-password> \
  -n observability --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deployment grafana -n observability
```

---

## Instrumenting apps

### Add the OTel SDK

```bash
npm install \
  @opentelemetry/sdk-node \
  @opentelemetry/auto-instrumentations-node \
  @opentelemetry/exporter-trace-otlp-proto \
  @opentelemetry/exporter-metrics-otlp-proto \
  @opentelemetry/exporter-logs-otlp-proto \
  @opentelemetry/sdk-metrics \
  @opentelemetry/sdk-logs \
  @opentelemetry/resources \
  @opentelemetry/semantic-conventions
```

### Copy the initializer

Copy `examples/telemetry.ts` into your app and import it as the first line of your entry point:

```typescript
import './telemetry';       // must be first
import express from 'express';
```

### Expose HOST_IP via the downward API

Add this environment variable to your app's Deployment container spec:

```yaml
env:
  - name: HOST_IP
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP
  - name: OTEL_SERVICE_NAME
    value: my-service-name
```

The `HOST_IP` routes SDK traffic to the node-local OTel Collector, which then enriches it with
pod/namespace metadata before forwarding to Loki, Tempo, and Prometheus.

### Log bridge (optional but recommended)

The SDK captures traces and metrics automatically via auto-instrumentation, but logs require a
bridge from your logging library:

```bash
# pino
npm install @opentelemetry/instrumentation-pino
# winston
npm install @opentelemetry/winston-transport
```

Without a log bridge, `console.log` output is not captured. Traces and metrics work regardless.

---

## Retention

All components are configured for 30-day retention:

| Component  | PVC size | Retention |
|------------|----------|-----------|
| Loki       | 20 Gi    | 30 days   |
| Tempo      | 10 Gi    | 30 days   |
| Prometheus | 20 Gi    | 30 days   |
| Grafana    | 5 Gi     | (dashboards, config) |

To change retention, update `retention_period` / `retention` in the relevant values file and
run `helm upgrade` again.

---

## Uninstall

```bash
helm uninstall grafana loki tempo prometheus alloy -n observability
kubectl delete -f observability/alloy/configmap.yaml
kubectl delete -f observability/collector/cluster-collector.yaml
kubectl delete -f observability/collector/daemonset.yaml
kubectl delete -f observability/collector/config.yaml
kubectl delete -f observability/collector/rbac.yaml
kubectl delete -f observability/lgtm/grafana-httproute.yaml
kubectl delete -f observability/namespace.yaml   # also removes all PVCs
```
