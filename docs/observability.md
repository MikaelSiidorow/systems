# Observability Stack

Metrics, logs, and traces for the K3s cluster, deployed as ArgoCD Applications with Helm chart sources.

## Architecture

```
                    +-----------+
                    |  Grafana  |  (grafana.miksu.app, VPN-only)
                    +-----+-----+
                          |
            +-------------+-------------+
            |             |             |
       Prometheus       Loki         Tempo
       (metrics)       (logs)       (traces)
            |             ^             ^
            |             |             |
            |         +---+---+     +---+---+
            |         | Alloy |---->| Alloy |
            |         | (pod  |     | (OTLP)|
            |         |  logs)|     +-------+
            |         +-------+         ^
            |             ^             |
            v             |             |
     kube targets    pod stdout    refinery app
                                  (OTLP HTTP)
```

**Data flow:**

- **Metrics**: Prometheus scrapes kube-state-metrics, node-exporter, and service monitors
- **Logs**: Alloy DaemonSet tails pod stdout/stderr, parses JSON, and pushes to Loki
- **Traces**: Refinery app sends OTLP to Alloy, which forwards to Tempo
- **OTLP logs**: Refinery app sends OTLP logs to Alloy, which converts and pushes to Loki

## Components

| Component             | Namespace    | Chart                                        | Version | Purpose                                                                        |
| --------------------- | ------------ | -------------------------------------------- | ------- | ------------------------------------------------------------------------------ |
| kube-prometheus-stack | `monitoring` | `prometheus-community/kube-prometheus-stack` | 82.4.3  | Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, operator |
| Loki                  | `loki`       | `grafana/loki`                               | 6.53.0  | Log aggregation (single-binary, filesystem storage)                            |
| Tempo                 | `tempo`      | `grafana/tempo`                              | 1.24.4  | Distributed tracing (single-binary, filesystem storage)                        |
| Alloy                 | `alloy`      | `grafana/alloy`                              | 1.6.0   | DaemonSet log collector + OTLP receiver/forwarder                              |

## Access

- **Grafana**: https://grafana.miksu.app (VPN-only via Headscale MagicDNS)
- **Credentials**: `admin` / password from `grafana-admin` K8s secret (managed by Terraform)

## Retention & Storage

All retention and storage settings are configured in the Helm values within each ArgoCD Application file.

| Component  | Retention       | PVC Size | Storage Class | Config Location                                                                               |
| ---------- | --------------- | -------- | ------------- | --------------------------------------------------------------------------------------------- |
| Prometheus | 7d              | 10Gi     | local-path    | `k8s/apps/kube-prometheus-stack.yaml` > `prometheus.prometheusSpec.retention` / `storageSpec` |
| Loki       | 7d (168h)       | 10Gi     | local-path    | `k8s/apps/loki.yaml` > `loki.limits_config.retention_period` / `singleBinary.persistence`     |
| Tempo      | 7d (168h)       | 10Gi     | local-path    | `k8s/apps/tempo.yaml` > `tempo.retention` / `persistence`                                     |
| Grafana    | N/A (stateless) | None     | -             | Dashboards/datasources come from Helm values, no persistence needed                           |

**Total storage**: ~30Gi for observability data across all PVCs.

To change retention, edit the relevant `k8s/apps/*.yaml` file and push — ArgoCD will sync automatically.

## Alerting

Alerts are routed to Telegram via Alertmanager.

- **Bot token**: Stored as K8s secret `alertmanager-telegram-token` in `monitoring` namespace (managed by Terraform, `terraform/k8s/secrets.tf`)
- **Chat ID**: Configured in `k8s/apps/kube-prometheus-stack.yaml` > `alertmanager.config.receivers`
- **Routing**: All alerts go to Telegram except `Watchdog` and `InfoInhibitor` (silenced)
- **Repeat interval**: 4h (won't spam)
- **Inhibition**: Critical alerts suppress matching warnings

Built-in kube-prometheus-stack alerts cover: pod crashes, node down, OOM kills, disk pressure, CPU throttling, etc.

## Resource Budget

| Component           | Memory Request | Memory Limit |
| ------------------- | -------------- | ------------ |
| Prometheus          | 512Mi          | 1Gi          |
| Grafana             | 128Mi          | 256Mi        |
| Alertmanager        | 32Mi           | 64Mi         |
| Prometheus Operator | 64Mi           | 128Mi        |
| node-exporter       | 32Mi           | 64Mi         |
| kube-state-metrics  | 32Mi           | 64Mi         |
| Loki                | 256Mi          | 512Mi        |
| Tempo               | 256Mi          | 512Mi        |
| Alloy               | 64Mi           | 128Mi        |
| **Total**           | **~1.4Gi**     | **~2.7Gi**   |

## Secrets (Terraform-managed)

| Secret                        | Namespace    | Terraform Variable       | GitHub Actions Secret    |
| ----------------------------- | ------------ | ------------------------ | ------------------------ |
| `grafana-admin`               | `monitoring` | `grafana_admin_password` | `GRAFANA_ADMIN_PASSWORD` |
| `alertmanager-telegram-token` | `monitoring` | `telegram_bot_token`     | `TELEGRAM_BOT_TOKEN`     |

Defined in `terraform/k8s/secrets.tf`, variables in `terraform/k8s/variables.tf`.

## K3s-Specific Notes

- `kubeEtcd`, `kubeScheduler`, `kubeControllerManager`, `kubeProxy` scrapers are disabled (K3s doesn't expose these metrics)
- `ServerSideApply=true` is required for kube-prometheus-stack and Loki (large CRDs)
- `grafana.miksu.app` DNS is via Headscale MagicDNS extra records (`infra/nixos/hosts/k8s-server/headscale.nix`)

## Datasource Correlation

Grafana datasources are pre-configured with cross-linking:

- **Log to Trace**: Loki has a derived field that extracts `trace_id` from JSON logs and links to Tempo
- **Trace to Log**: Tempo links back to Loki for related logs
- **Trace to Metrics**: Tempo links to Prometheus for service metrics
- **Node graph / Service map**: Enabled on Tempo datasource

## Files

```
k8s/apps/
  kube-prometheus-stack.yaml   # Prometheus, Grafana, Alertmanager
  loki.yaml                    # Log aggregation
  tempo.yaml                   # Trace storage
  alloy.yaml                   # Log/trace collector

terraform/k8s/
  secrets.tf                   # Grafana + Telegram secrets
  variables.tf                 # Secret variable declarations

infra/nixos/hosts/k8s-server/
  headscale.nix                # grafana.miksu.app MagicDNS record

.github/workflows/
  deploy.yml                   # CI passes TF_VAR_* secrets
```
