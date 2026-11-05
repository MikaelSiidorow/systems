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
- **Hestia**: the host's Alloy (`infra/nixos/hosts/hestia/monitoring.nix`) ships host metrics and the journal, and accepts OTLP from local agents on `127.0.0.1:4318`. It forwards everything over the tailnet to the cluster Alloy (`100.64.0.1:4318`) through an on-disk queue that retries for 24h, so a cluster or tailnet outage delays data instead of dropping it

## Agent telemetry

Claude Code and Codex on Hestia and tpad send traces, events and metrics to a local Alloy queue at `127.0.0.1:4318`, which forwards them to the cluster Alloy. On Hestia that is the host's own Alloy; on tpad it is a user service with the same disk queue and 24h of retries (`workstations/hosts/tpad/telemetry.nix`), so data from the laptop arrives once it is back online. A host opts in by setting `agents.telemetry` (`modules/home/agents/config.nix`), which adds the OTel settings to both agents' config baselines. Other hosts leave it unset; on the Mac that keeps work sessions off the cluster.

- **Claude Code**: spans per prompt (`claude_code.interaction`), LLM request and tool call, with file paths and branch and SHA on commits. Tool events carry each tool's input (`OTEL_LOG_TOOL_DETAILS`): Bash commands, MCP arguments, Write contents and Edit strings, each cut at 512 characters, plus the error text when a tool fails. Events carry `session.id` and `prompt.id`; everything carries `host.name` and the repository (`vcs.repository.name`). Prompt text and successful tool output are not exported.
- **Codex**: `codex.*` log events, traces and metrics, tagged with the host as `environment`. Tool events carry the tool call, including shell commands, and a snippet of its output. Prompt text is not exported.
- **T3 Code** (Hestia only, `otlpTracesUrl` in `modules/t3code.nix`): T3's own spans as `t3code-server`, traces only. Hestia's Alloy drops all but the turn, adapter, Codex app-server and dispatch spans, since T3 otherwise traces every sqlite query and git call.

Both agents send delta metrics, which Prometheus cannot store. The cluster Alloy turns them cumulative with `otelcol.processor.deltatocumulative` before remote write, so it runs with `stabilityLevel: experimental`. A stream idle for 5 minutes is dropped and restarts from zero, which `rate()` and `increase()` treat as a counter reset.

Find a session in Tempo with TraceQL, e.g. `{ resource.host.name = "hestia" && name = "claude_code.tool" }`, or in Loki by `session_id`.

To turn telemetry off on a host, unset the option and delete the `OTEL_*` and `CLAUDE_CODE_*TELEMETRY*` keys from `~/.claude/settings.json` and the `[otel]` table from `~/.codex/config.toml`. The settings merge only adds keys.

For the Mac, the plan is a local collector (a launchd OTLP receiver writing to disk or a local store) with `agents.telemetry.endpoint` pointed at `http://127.0.0.1:4318`.

## Components

| Component             | Namespace    | Chart                                        | Version | Purpose                                                                        |
| --------------------- | ------------ | -------------------------------------------- | ------- | ------------------------------------------------------------------------------ |
| kube-prometheus-stack | `monitoring` | `prometheus-community/kube-prometheus-stack` | 92.0.0  | Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, operator |
| Loki                  | `loki`       | `grafana-community/loki`                     | 18.13.8 | Log aggregation (single-binary, filesystem storage)                            |
| Tempo                 | `tempo`      | `grafana-community/tempo`                    | 3.1.0   | Distributed tracing (single-binary, filesystem storage)                        |
| Alloy                 | `alloy`      | `grafana/alloy`                              | 1.13.0  | DaemonSet log collector + OTLP receiver/forwarder                              |

## Access

- **Grafana**: https://grafana.miksu.app (VPN-only via Headscale MagicDNS)
- **Credentials**: `admin` / password from `grafana-admin` K8s secret (managed by Terraform)
- **Anonymous read**: anyone who can reach Grafana views it as a Viewer without logging in (`grafana.ini` `auth.anonymous` in `k8s/apps/kube-prometheus-stack.yaml`). Editing and admin still need the login. Agents query through the datasource proxy, `/api/datasources/proxy/uid/{tempo,loki,prometheus}/...`; the `grafana-datasource-proxy-guard` IngressRoute lets only reads through it and the datasource resource route, because they otherwise reach endpoints like Loki's `/ingester/shutdown` and Prometheus's `/-/quit`.
- **Who reaches it**: personal devices (`mikael@`), CI (`tag:ci`) and Hestia, which carries `tag:telemetry-reader` next to `tag:home-subnet-router` so its agents can read their own telemetry. CI only needs 443 for the deploy smoke test, but anonymous read cannot be limited by source, so its runners can read telemetry too (including agent Bash commands in Loki). Accepted: they join the tailnet only for deploy jobs on main. Tags are set on the server: `sudo headscale nodes list`, then `sudo headscale nodes tag -i <id> -t tag:home-subnet-router -t tag:telemetry-reader` on k8s-server (list every tag the node keeps).
- **Revoke**: drop the `tag:telemetry-reader` rule in `infra/nixos/hosts/k8s-server/headscale.nix`, or retag Hestia with only `tag:home-subnet-router`. Turning `auth.anonymous` off closes it for every client.

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
