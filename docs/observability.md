# Observability Stack

Metrics, logs, and traces for the K3s cluster, deployed as Flux HelmReleases (`k8s/monitoring/`, reconciled by the `monitoring` Kustomization in `k8s/clusters/olympus/`).

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

Claude Code and Codex on Hestia and tpad send traces, events and metrics, and Antigravity traces, to a local Alloy queue at `127.0.0.1:4318`, which forwards them to the cluster Alloy. On Hestia that is the host's own Alloy; on tpad it is a user service with the same disk queue and 24h of retries (`workstations/hosts/tpad/telemetry.nix`), so data from the laptop arrives once it is back online. A host opts in by setting `agents.telemetry` (`modules/home/agents/config.nix`), which adds the OTel settings to both agents' config baselines and installs the `agent-traces` skill. The Mac sends to its own stack instead (below), so work sessions never reach the cluster.

- **Claude Code**: spans per prompt (`claude_code.interaction`), LLM request and tool call, with file paths and branch and SHA on commits. Tool events carry each tool's input (`OTEL_LOG_TOOL_DETAILS`): Bash commands, MCP arguments, Write contents and Edit strings, each cut at 512 characters, plus the error text when a tool fails. Bash results carry no exit code, only `success` and the error text. Events carry `session.id` and `prompt.id`; everything carries `host.name` and the repository (`vcs.repository.name`). A subagent shares its parent's session and trace, and a `subagent_completed` event closes it. Claude's Bash children inherit `TRACEPARENT`, and T3 sets it for the agents it starts, so a `claude` or `codex` run from an agent shell joins the parent's trace as a separate session.
- **Codex**: `codex.*` log events, traces and metrics, tagged with the host as `environment`. Codex metrics carry the host only as the resource attribute `env`; the cluster Alloy copies it onto each point, so Prometheus series carry `host_name` and hosts do not collide. Tool events carry the tool call, including shell commands, and a snippet of its output.
- **T3 Code** (Hestia and the Mac, `otlpTracesUrl` in `modules/t3code`): T3's own spans as `t3code-server`, traces only. Hestia's and the Mac's Alloy drop all but the turn, adapter, Codex app-server and dispatch spans, since T3 otherwise traces every sqlite query and git call. Hestia's raw archive keeps them all.
- **Antigravity** (Hestia and tpad): `agy` has no OTel export, so hooks in `~/.gemini/config/hooks.json` run `modules/home/agents/antigravity/otel-hook.sh`, which sends OTLP spans as service `antigravity`: a turn (`antigravity.interaction`) with a child per tool call and per model invocation; an invocation span may include the tools that call ran, so it is not model latency. A `TRACEPARENT` in its environment parents the turn and `T3CODE_THREAD_ID` sets `t3.thread_id`. T3 passes the thread ID but not the trace, so a patch in `modules/t3code/patches.nix` adds `TRACEPARENT` when T3 starts `agy`. That process lasts the whole thread, so every turn sits under the thread's first turn span, as with Claude. T3 gives `agy` a private Gemini home per provider instance (`~/.t3/*/providers/antigravity/*/`), so each switch links `AGENTS.md` and `config/hooks.json` from `~/.gemini` into it; an instance added later gets them on the next switch. Agents should not run `agy` themselves: Google bans accounts for third-party use. Hooks see no token counts, cost or tool output, so there are no events or metrics; tool input and error text follow `toolDetails`.

Both agents send delta metrics, which Prometheus cannot store. The cluster Alloy turns them cumulative with `otelcol.processor.deltatocumulative` before remote write, so it runs with `stabilityLevel: experimental`. A stream idle for 5 minutes is dropped and restarts from zero, which `rate()` and `increase()` treat as a counter reset.

Find a session in Tempo with TraceQL, e.g. `{ resource.host.name = "hestia" && name = "claude_code.tool" }`, or in Loki by `session_id`.

To turn telemetry off on a host, unset the option and delete the `OTEL_*`, `CLAUDE_CODE_*TELEMETRY*` and `GRAFANA_URL` keys from `~/.claude/settings.json`, the `[otel]` table from `~/.codex/config.toml`, and the `read_url(grafana…)` rule from `~/.gemini/antigravity-cli/settings.json`, which also opens Antigravity's sandbox to Grafana. The settings merge only adds keys. Also delete the `config/hooks.json` links under `~/.t3/*/providers/antigravity/*/`.

### Content

`agents.telemetry.content` (off by default; on for Hestia and tpad) makes the agents export content too: Claude's prompts and responses (`OTEL_LOG_USER_PROMPTS`) and tool output (`OTEL_LOG_TOOL_CONTENT`, a `tool.output` span event on the tool span with Bash output, Read and Write contents and diffs, cut at 60 KB), and Codex's prompts and responses (`log_user_prompt`, `log_agent_responses`). Claude's settings go in the `env` block of `~/.claude/settings.json`, which overrides the process environment, and turning the option off writes `0`, since the merge never removes a key.

Content never reaches the cluster, where Grafana is readable without a login by every tailnet device, CI runners included. Hestia's and tpad's Alloy drop the `tool.output` span events and the `prompt`, `prompt_text`, `user_prompt` and `response` attributes before forwarding (`modules/agent-telemetry-alloy.nix`). They also drop the system prompt, context and request and response bodies that Claude's detailed beta tracing (`ENABLE_BETA_TRACING_DETAILED`) and `OTEL_LOG_RAW_API_BODIES` would add if a shell turned them on. Anything else a future agent version adds under a new name would pass, so recheck the list when turning on a new content setting. Commands, tool input, error text and Codex tool output snippets still go to the cluster, as before. Content lives only in the host's archive (below), the transcripts and, on Hestia, Saha.

### Raw archive

Hestia's and tpad's Alloy also write everything the agents send to local disk, before the T3 span filter and content stripping, so it can be replayed later: Hestia's in `/var/lib/alloy/archive` (a `DynamicUser` service, so reading it needs root), tpad's in `~/.local/state/alloy/archive`. The service umask keeps them 0700 and 0600, since they hold prompts and tool output. Host metrics and the journal are not archived.

There is one file per signal, `traces.otlp`, `logs.otlp` and `metrics.otlp`. Each is a run of records: a 4-byte big-endian length, then a zstd frame holding one OTLP/JSON export request, one 10-second batch. Decompressed, a record is one line in the format the OTLP JSON file receiver reads. Traces rotate at 100 MiB, logs and metrics at 10 MiB, into `<signal>-<timestamp>-size.otlp`. Rotated files are deleted 90 days after rotation, or past 150 trace and 20 log or metric backups, which caps the archive at about 16 GB. Rotation goes by size only, so a quiet file, such as tpad's or Hestia's logs, can hold data older than 90 days until it fills.

Hestia's agents send about 1.8 million spans a day, nearly all unfiltered T3 spans, about 1.7 GB of OTLP/JSON. Compressed in 10-second batches (about 16x on captured agent sessions), the archive should grow about 110 MB a day, so 90 days fit under the cap. The archive does not depend on the cluster or the tailnet being up. tpad, without T3 traces, writes a few MB a day.

Read it with a few lines of Python (`zstandard`):

```python
import struct, sys, zstandard
for path in sys.argv[1:]:
    with open(path, "rb") as f:
        while header := f.read(4):
            frame = f.read(struct.unpack(">I", header)[0])
            print(zstandard.ZstdDecompressor().decompressobj().decompress(frame).decode())
```

### Saha

Saha is an agent-session console under development. On Hestia its ingest runs as a dev process on `127.0.0.1:4319`, not as a service. With `services.saha-export.enable` (`infra/nixos/hosts/hestia/saha.nix`, on in `monitoring.nix`), Hestia's Alloy sends it every agent signal as the agents sent it, before the T3 span filter and content stripping. It goes over loopback only, so content stays on the host, as with the archive.

- **Token**: a bearer token from `infra/secrets/saha.yaml` (sops), decrypted to `/run/secrets/saha-ingest-token`, readable by the user, and passed to Alloy as the systemd credential `saha-ingest-token`. It must match the hash Saha stores for its ingest user (`dev`). To rotate: generate a token, `sops infra/secrets/saha.yaml` to replace it (no trailing newline), store its hash in Saha, then deploy; sops-nix restarts Alloy. Batches sent with the old token in between get a 401 and are dropped, not retried.
- **Saha down**: batches wait on disk in the shared `otelcol.storage.file.queue`, in files of their own (the storage keys them by exporter and signal, so the cluster queue is unaffected). The queue is capped at 512 MiB, about 6 hours of unfiltered T3 spans; each batch in flight retries for 6 hours. Once the queue is full, Alloy drops each new batch and logs an error for it, about one a second. The archive keeps everything, so replay it to fill a gap. If Saha will be down for more than a few hours, turn the option off and deploy.
- **Turning it off**: setting the option to false removes the exporter and the credential. Its queue files (named after `otelcol.exporter.otlphttp.saha`) stay under `/var/lib/alloy/data-alloy` until deleted by hand.

### Transcripts

Full transcripts stay as the agents' own JSONL files. They never reach the cluster, where Grafana is readable without a login. Hestia and tpad set `agents.keepTranscripts`, which keeps Claude's `~/.claude/projects` for ten years instead of 30 days; Codex never prunes `~/.codex/sessions`. Every hour tpad copies both to Hestia's `~/agent-transcripts/tpad/{claude,codex}`, plus Antigravity's conversations to `antigravity-cli` and `antigravity-t3-<instance>`, without its OAuth token (`workstations/hosts/tpad/transcripts.nix`). Its key reaches only `rrsync`, which can write files there but not read them, run deletes or plant working symlinks. Run `transcripts-push` on tpad to copy now.

A file maps to a session in telemetry: Claude's file name is its `session.id`, and Codex's ends with its thread id. Query the files in place with DuckDB. Record shapes vary too much for `read_json` to infer columns, so read raw objects, and skip the occasional line an interrupted session left half-written: `nix shell nixpkgs#duckdb -c duckdb -c "select json->>'type' as type, count(*) from read_ndjson_objects('~/.claude/projects/*/*.jsonl', ignore_errors = true) group by all"`. Codex files are at `~/.codex/sessions/*/*/*/*.jsonl`.

### On the Mac

`workstations/hosts/mbp/telemetry.nix` runs Alloy, Loki, Tempo, Prometheus and Grafana from nixpkgs as launchd agents, every one bound to 127.0.0.1, with nothing exported off the machine. Alloy receives OTLP on 4318 and repeats the cluster pipeline, so the skill's labels and metric names hold. Grafana is at http://127.0.0.1:43000 with anonymous read access and the cluster's datasource UIDs; the backends sit on 43090–43345. Data lives in `~/.local/state/agent-telemetry` for 90 days, with Prometheus also capped at 20 GB; Loki and Tempo expire by age only.

- **No content**: the Mac sets `toolDetails = false`, so Claude exports no Bash commands or tool input, and Codex no tool output or prompts. Codex still sends each command in `arguments`, which no setting turns off, so Alloy deletes `prompt`, `prompt_text`, `user_prompt`, `response`, `body`, `tool_input`, `tool_parameters`, `arguments`, `output`, `full_command` and `error`, and blanks span status messages, before storing anything. Failed tools still show as `success=false`, without the error text.
- **Reading it**: `agents.telemetry.grafana` and `grafanaSocket` set `GRAFANA_URL` and `GRAFANA_SOCKET` for both agents, and `q` connects through the socket (`~/.local/state/agent-telemetry/grafana.sock`, a `socat` forwarder to Grafana's port). The sandboxes allow only that socket: allowing 127.0.0.1 would open every local port, including SSH tunnels and CLIProxyAPI.
- **Exposure**: the backend APIs have no auth and no Host check, so a local process or a DNS-rebinding web page could read them. Grafana rejects other Host names, and Loki's delete API is off.
- **Logs**: each service writes to `stdout.log` and `stderr.log` in its state folder; `launchctl print gui/$(id -u)/org.nix-community.home.telemetry-<name>` shows its state.

## Components

| Component             | Namespace    | Chart                                        | Version | Purpose                                                                        |
| --------------------- | ------------ | -------------------------------------------- | ------- | ------------------------------------------------------------------------------ |
| kube-prometheus-stack | `monitoring` | `prometheus-community/kube-prometheus-stack` | 92.0.0  | Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics, operator |
| Loki                  | `loki`       | `grafana-community/loki`                     | 18.13.8 | Log aggregation (single-binary, filesystem storage)                            |
| Tempo                 | `tempo`      | `grafana-community/tempo`                    | 3.1.0   | Distributed tracing (single-binary, filesystem storage)                        |
| Alloy                 | `alloy`      | `grafana/alloy`                              | 1.13.0  | DaemonSet log collector + OTLP receiver/forwarder                              |

## Access

- **Grafana**: https://grafana.miksu.app (VPN-only via Headscale MagicDNS)
- **Credentials**: `admin` / password from `grafana-admin` K8s secret (`k8s/monitoring/grafana-admin.sops.yaml`)
- **Anonymous read**: anyone who can reach Grafana views it as a Viewer without logging in (`grafana.ini` `auth.anonymous` in `k8s/monitoring/kube-prometheus-stack.yaml`). Editing and admin still need the login. Agents query through the datasource proxy, `/api/datasources/proxy/uid/{tempo,loki,prometheus}/...`; the `grafana-datasource-proxy-guard` IngressRoute lets only reads through it and the datasource resource route, because they otherwise reach endpoints like Loki's `/ingester/shutdown` and Prometheus's `/-/quit`.
- **Who reaches it**: personal devices (`mikael@`), CI (`tag:ci`) and Hestia, which carries `tag:telemetry-reader` next to `tag:home-subnet-router` so its agents can read their own telemetry. CI only needs 443 for the deploy smoke test, but anonymous read cannot be limited by source, so its runners can read telemetry too (including agent Bash commands in Loki). Accepted: they join the tailnet only for deploy jobs on main. Tags are set on the server: `sudo headscale nodes list`, then `sudo headscale nodes tag -i <id> -t tag:home-subnet-router -t tag:telemetry-reader` on olympus (list every tag the node keeps).
- **Revoke**: drop the `tag:telemetry-reader` rule in `infra/nixos/hosts/olympus/headscale.nix`, or retag Hestia with only `tag:home-subnet-router`. Turning `auth.anonymous` off closes it for every client.

## Retention & Storage

All retention and storage settings are configured in the Helm values of each HelmRelease.

| Component  | Retention       | PVC Size | Storage Class | Config Location                                                                                     |
| ---------- | --------------- | -------- | ------------- | --------------------------------------------------------------------------------------------------- |
| Prometheus | 7d              | 10Gi     | local-path    | `k8s/monitoring/kube-prometheus-stack.yaml` > `prometheus.prometheusSpec.retention` / `storageSpec` |
| Loki       | 7d (168h)       | 10Gi     | local-path    | `k8s/monitoring/loki.yaml` > `loki.limits_config.retention_period` / `singleBinary.persistence`     |
| Tempo      | 7d (168h)       | 10Gi     | local-path    | `k8s/monitoring/tempo.yaml` > `tempo.retention` / `persistence`                                     |
| Grafana    | N/A (stateless) | None     | -             | Dashboards/datasources come from Helm values, no persistence needed                                 |

**Total storage**: ~30Gi for observability data across all PVCs.

To change retention, edit the relevant `k8s/monitoring/*.yaml` file and push — Flux upgrades the release automatically.

## Alerting

Alerts are routed to Telegram via Alertmanager.

- **Bot token**: Stored as K8s secret `alertmanager-telegram-token` in `monitoring` namespace, from `k8s/monitoring/alertmanager-telegram-token.sops.yaml`. Gatus uses the same bot token from `k8s/gatus/gatus-telegram-token.sops.yaml`, so rotating it means editing both files with `sops`, then rolling `gatus` to reload its env var.
- **Chat ID**: Configured in `k8s/monitoring/kube-prometheus-stack.yaml` > `alertmanager.config.receivers`
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

## Secrets (SOPS, decrypted by Flux)

| Secret                        | Namespace    | File                                                   |
| ----------------------------- | ------------ | ------------------------------------------------------ |
| `grafana-admin`               | `monitoring` | `k8s/monitoring/grafana-admin.sops.yaml`               |
| `alertmanager-telegram-token` | `monitoring` | `k8s/monitoring/alertmanager-telegram-token.sops.yaml` |

Edit with `sops <file>`; both are encrypted to your post-quantum age key and olympus's.

## K3s-Specific Notes

- `kubeEtcd`, `kubeScheduler`, `kubeControllerManager`, `kubeProxy` scrapers are disabled (K3s doesn't expose these metrics)
- The HelmReleases set `crds: CreateReplace`, so chart upgrades also update the kube-prometheus-stack CRDs
- `grafana.miksu.app` DNS is via Headscale MagicDNS extra records (`infra/nixos/hosts/olympus/headscale.nix`)

## Datasource Correlation

Grafana datasources are pre-configured with cross-linking:

- **Log to Trace**: Loki has a derived field that extracts `trace_id` from JSON logs and links to Tempo
- **Trace to Log**: Tempo links back to Loki for related logs
- **Trace to Metrics**: Tempo links to Prometheus for service metrics
- **Node graph / Service map**: Enabled on Tempo datasource

## Files

```
k8s/clusters/olympus/
  monitoring.yaml              # Flux Kustomization for k8s/monitoring

k8s/monitoring/
  kube-prometheus-stack.yaml   # Prometheus, Grafana, Alertmanager
  loki.yaml                    # Log aggregation
  tempo.yaml                   # Trace storage
  alloy.yaml                   # Log/trace collector
  repositories.yaml            # Helm chart repositories
  namespaces.yaml              # monitoring, loki, tempo, alloy (never pruned)
  *.sops.yaml                  # Grafana admin + Telegram token

infra/nixos/hosts/olympus/
  headscale.nix                # grafana.miksu.app MagicDNS record
```
