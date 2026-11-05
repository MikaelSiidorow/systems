---
name: agent-traces
description: Query Claude Code and Codex telemetry from Hestia in Tempo, Loki and Prometheus. Use when asked what a past or current agent session ran, which tool calls failed or were slow, or what sessions cost.
---

# Agent traces

Claude Code and Codex on Hestia export telemetry to the cluster. Read it through Grafana's read-only datasource proxy with `q`, the script beside this file:

```sh
q <tempo|loki|prometheus> <api-path> [name=value ...]   # GET, values URL-encoded
```

Pipe every response through `jq` and print only the fields you need: a raw trace is megabytes. If `q` times out, the host cannot reach `grafana.miksu.app` (see `docs/observability.md` in the systems repo); say so rather than guessing.

## Where things live

| Want | Claude Code | Codex |
| --- | --- | --- |
| This session's id | `$CLAUDE_CODE_SESSION_ID` (span and event `session.id`) | `$CODEX_THREAD_ID` (event `conversation.id`) |
| Prompts, tool calls, errors | Loki events, `{service_name="claude-code"}` | Loki events, `{service_name=~"codex.*"}` |
| Durations, structure | Tempo spans, one trace per prompt | Loki `duration_ms`; its spans are internal plumbing |
| Tokens, cost | Prometheus, or Loki `api_request` | Loki `codex.sse_event` `response.completed` |

Data arrives seconds after the fact, and the current prompt's `claude_code.interaction` span lands only when the prompt ends. Retention is 7 days. `TRACEPARENT` is not set in agent shells; use the session id.

Claude Code tool spans: `claude_code.tool` carries `tool_name` and, for Bash, `full_command`; its child `claude_code.tool.execution` carries `success` and `error`. Span status stays unset on failure, so filter on `span.success = false`, never `status = error`. Every span has `span.session.id` and, inside a repo, `span.vcs.repository.name`.

Codex reports a failed shell command as `success=true` with `Process exited with code N` in `output`; match on the exit code.

## Recipes

Set `T0=$(date -d '-1 day' +%s) T1=$(date +%s)` for Tempo windows. Loki takes `since=6h` style windows.

**Latest Claude sessions** (one row per prompt):

```sh
q tempo /api/search q='{ name = "claude_code.interaction" && resource.host.name = "hestia" } | select(span.session.id, span.vcs.repository.name)' start=$T0 end=$T1 limit=20 \
  | jq -r '.traces[] | [(.startTimeUnixNano|tonumber/1e9|todate), .traceID, (.spanSets[0].spans[0].attributes|map({(.key): (.value|.[keys[0]])})|add|.["session.id"], .["vcs.repository.name"])] | @tsv'
```

**Claude session timeline** (prompts, tool calls with commands, outcome, errors):

```sh
S=$CLAUDE_CODE_SESSION_ID
q loki /loki/api/v1/query_range query="{service_name=\"claude-code\"} | session_id=\"$S\" | event_name=~\"user_prompt|tool_result|api_error\"" since=24h limit=500 direction=forward \
  | jq -r '[.data.result[] | .stream as $s | .values[] | $s + {ts: .[0]}] | sort_by(.ts)[] | [.event_timestamp, .event_name, .tool_name // "", .success // "", .duration_ms // "", (.tool_input // "" | .[0:120]), .error // ""] | @tsv'
```

**Failed Claude tool calls** over a window (add `| vcs_repository_name="systems"` to scope a repo):

```sh
q loki /loki/api/v1/query_range query='{service_name="claude-code"} | event_name="tool_result" | success="false"' since=24h limit=100 \
  | jq -r '.data.result[] | .stream | [.event_timestamp, .session_id[0:8], .vcs_repository_name // "", .tool_name, (.tool_input|.[0:120]), .error] | @tsv'
```

**Slowest Claude commands**:

```sh
q tempo /api/search q='{ name = "claude_code.tool" && span.tool_name = "Bash" && duration > 30s } | select(span.full_command, span.session.id)' start=$T0 end=$T1 limit=50 spss=20 \
  | jq -r '[.traces[].spanSets[].spans[] | {d: (.durationNanos|tonumber/1e9), a: (.attributes|map({(.key): (.value|.[keys[0]])})|add)}] | sort_by(-.d)[:20][] | [.d, .a["session.id"][0:8], .a.full_command[0:120]] | @tsv'
```

**Claude cost and tokens** by model or session (`type` is `input`, `output`, `cacheRead` or `cacheCreation`):

```sh
q prometheus /api/v1/query query='sum by (model) (increase(claude_code_cost_usage_USD_total[1d]))' | jq -r '.data.result[] | [.metric.model, .value[1]] | @tsv'
q prometheus /api/v1/query query='sum by (session_id, type) (increase(claude_code_token_usage_tokens_total[1d]))' | jq -r '.data.result[] | [.metric.session_id, .metric.type, .value[1]] | @tsv'
```

**Codex session timeline** (`$CODEX_THREAD_ID` for this one; drop the id filter to list recent ones):

```sh
C=$CODEX_THREAD_ID
q loki /loki/api/v1/query_range query="{service_name=~\"codex.*\"} | conversation_id=\"$C\" | event_name=~\"codex.(user_prompt|tool_result)\"" since=24h limit=500 direction=forward \
  | jq -r '[.data.result[] | .stream as $s | .values[] | $s + {ts: .[0]}] | sort_by(.ts)[] | [.event_timestamp, .event_name, .tool_name // "", .duration_ms // "", (.arguments // "" | .[0:120]), (.output // "" | capture("exited with code (?<c>[0-9]+)").c // "")] | @tsv'
```

**Failed Codex commands**: the same query with `| output=~"(?s).*exited with code [1-9].*"`. **Codex tokens**: `| event_name="codex.sse_event" | event_kind="response.completed" | input_token_count!=""` and read `input_token_count`, `output_token_count`, `cached_token_count`.

**Trace to events and back**: a Claude prompt's events carry its trace id, so `| trace_id="<traceID>"` in Loki lists one prompt's events, and `prompt_id` groups them across retries. From an event, `q tempo /api/v2/traces/<trace_id>` returns its spans; extract only names, durations and the attributes you need.
