---
name: agent-traces
description: Query Claude Code and Codex telemetry from Hestia, tpad or the Mac in Tempo, Loki and Prometheus. Use when asked what a past or current agent session ran, which tool calls failed or were slow, or what sessions cost.
---

# Agent traces

Claude Code and Codex on Hestia and tpad export telemetry to the cluster; tpad's arrives late when it has been offline. The Mac keeps its own in a local stack, which `q` reads through `$GRAFANA_SOCKET`; there tool details are off, so command, output and error-text fields (`tool_input`, `full_command`, `arguments`, `output`, `exit`, `error`) are empty, and a failed Codex command shows only when it fails before launch. Every signal carries its host: `resources_host_name` in Loki after `| json`, `resource.host.name` in Tempo, `host_name` on Claude metrics. Read it with `q`, the script beside this file, which goes through Grafana's read-only datasource proxy. Shell state does not carry between commands, so start every command with the PATH line:

```sh
export PATH="$HOME/.claude/skills/agent-traces:$HOME/.codex/skills/agent-traces:$PATH"
q spans '<traceql>' [since=24h] [limit=50]    # Tempo: one JSON line per matched span
q events '<logql>' [since=24h] [limit=500]    # Loki: newest `limit` events, oldest first
q <tempo|loki|prometheus> <api-path> [k=v...] # raw GET
```

Pipe the output through `jq` and print only the fields the question needs. If `q` fails with `Connection timed out`, `Could not resolve host` or `Failed to connect`, this host cannot reach Grafana (`$GRAFANA_URL`, else `grafana.miksu.app`): say so instead of guessing. `Operation timed out` means the query was too slow: narrow the window or add a `|=` line filter. When a result reaches its limit, `q` warns on stderr: raise the limit or narrow the window before treating it as complete.

## Where things live

- **This session**: `$CLAUDE_CODE_SESSION_ID` is the Claude `session_id`; `$CODEX_THREAD_ID` is the Codex `conversation_id`. `TRACEPARENT` is not set in agent shells.
- **Claude Code events** in Loki: `{job="claude-code"}`, one JSON line per event. Parse with `| json`; attributes become `attributes_<name>` with dots as underscores (`attributes_session_id`, `attributes_event_name`, `attributes_vcs_repository_name`). `q events` strips the prefix. Events: `user_prompt` (prompt text redacted), `tool_result` (`tool_name`, `tool_input`, `success`, `duration_ms`, `error`), `api_request` (`model`, `cost_usd`, `*_tokens`), `api_error`.
- **Claude Code spans** in Tempo: one trace per prompt, rooted at `claude_code.interaction`. `claude_code.tool` carries `tool_name` and, for Bash, `full_command`; its child `claude_code.tool.execution` carries `success` and `error`. Span status stays unset on failure. Every span has `span.session.id` and, in a repo, `span.vcs.repository.name`.
- **Codex events** in Loki: `{job=~"codex.*|T3 Code"}`, same JSON shape: `codex_exec` for `codex exec`, `codex-app-server` for the app, `T3 Code` for Codex under T3. Each sends `codex.user_prompt`, `codex.tool_result` (`tool_name` is `exec` or `exec_command` for commands; `arguments`, `output`, `duration_ms`), `codex.sse_event` and `codex.api_request`. A command that runs and fails still reports `success=true` (only failures before launch set `success=false`); the exit code is in `output` (`Process exited with code N`), which `q events` parses into `exit`. Codex spans are internal plumbing; use the events.
- **Metrics** in Prometheus: `claude_code_{token_usage_tokens,cost_usage_USD,session_count,active_time_seconds}_total`, labelled `host_name`, `model`, `session_id`, `type` (token kind) and `vcs_repository_name`; `codex_*` carry `model` and `host_name` but no session. Agents export about once a minute and only while a value changes, and a series idle over 5 minutes restarts from zero, so instant queries and short windows return little: use `max_over_time` over a window. That sums each session's peak counter, so it is approximate: it includes usage from before the window and, across a restart, keeps only the larger segment. For exact or per-session totals, use Loki.
- **Lag and retention**: data lands seconds after the fact, and an `interaction` span only when its prompt ends, so use Loki for the prompt in flight. Retention is 7 days on the cluster and 90 on the Mac.

## Recipes

Latest Claude sessions (add `| attributes_vcs_repository_name="systems"` to scope a repo):

```sh
q events '{job="claude-code"} |= "user_prompt" | json | attributes_event_name="user_prompt"' 2d 1000 \
  | jq -s -r 'group_by(.session_id) | map({s: .[0].session_id, repo: .[0].vcs_repository_name, last: .[-1].event_timestamp, prompts: length}) | sort_by(.last)[-10:][] | [.last, .s, .repo, .prompts] | @tsv'
```

One Claude session's timeline:

```sh
S=$CLAUDE_CODE_SESSION_ID
q events "{job=\"claude-code\"} |= \"$S\" | json | attributes_event_name=~\"user_prompt|tool_result|api_error\"" 7d \
  | jq -r '[.event_timestamp, .event_name, .tool_name // "", .success // "", .duration_ms // "", (.tool_input // "" | .[0:120]), .error // ""] | @tsv'
```

Failed Claude tool calls in a window:

```sh
q events '{job="claude-code"} |= "tool_result" | json | attributes_event_name="tool_result" | attributes_success="false"' 24h 100 \
  | jq -r '[.event_timestamp, .session_id[0:8], .vcs_repository_name // "", .tool_name, (.tool_input | .[0:120]), .error] | @tsv'
```

Slowest Claude commands:

```sh
q spans '{ name = "claude_code.tool" && span.tool_name = "Bash" && duration > 60s } | select(span.full_command, span.session.id, span.vcs.repository.name)' 7d 500 \
  | jq -s -r 'sort_by(-.dur_s)[:10][] | [.dur_s, .["session.id"][0:8], .["vcs.repository.name"], .full_command[0:120]] | @tsv'
```

Claude cost by model or by session (swap `cost_usd` for `input_tokens`, `output_tokens`, `cache_read_tokens` or `cache_creation_tokens`):

```sh
q loki /loki/api/v1/query query='sum by (attributes_model) (sum_over_time({job="claude-code"} |= "api_request" | json | attributes_event_name="api_request" | unwrap attributes_cost_usd [1d]))' \
  | jq -r '.data.result[] | [.metric.attributes_model, .value[1]] | @tsv'
q loki /loki/api/v1/query query='topk(10, sum by (attributes_session_id, attributes_vcs_repository_name) (sum_over_time({job="claude-code"} |= "api_request" | json | attributes_event_name="api_request" | unwrap attributes_cost_usd [7d])))' \
  | jq -r '.data.result[] | [.metric.attributes_session_id, .metric.attributes_vcs_repository_name, .value[1]] | @tsv'
```

Approximate tokens and cost of sessions active in a window, by model or host (Codex: `sum by (model, token_type) (max_over_time(codex_turn_token_usage_sum[7d]))`):

```sh
q prometheus /api/v1/query query='sum by (model, type) (max_over_time(claude_code_token_usage_tokens_total[1d]))' \
  | jq -r '.data.result[] | [.metric.model, .metric.type, .value[1]] | @tsv'
q prometheus /api/v1/query query='sum by (host_name, model) (max_over_time(claude_code_cost_usage_USD_total[7d]))' \
  | jq -r '.data.result[] | [.metric.host_name, .metric.model, .value[1]] | @tsv'
```

Codex sessions, then one session's timeline (`q events` adds `exit`, the command's exit code):

```sh
q events '{job=~"codex.*|T3 Code"} | json | attributes_event_name="codex.user_prompt"' 7d | jq -r '[.event_timestamp, .conversation_id, .model] | @tsv'
C=$CODEX_THREAD_ID
q events "{job=~\"codex.*|T3 Code\"} |= \"$C\" | json | attributes_event_name=~\"codex.(user_prompt|tool_result)\"" 7d \
  | jq -r '[.event_timestamp, .event_name, .tool_name // "", .duration_ms // "", (.arguments // "" | .[0:120]), "exit=" + (.exit // "")] | @tsv'
```

Failed Codex commands:

```sh
q events '{job=~"codex.*|T3 Code"} | json | attributes_event_name="codex.tool_result" | attributes_tool_name=~"exec(_command)?" | (attributes_success="false" or attributes_output=~"(?s)([^\n]*\n){0,3}Process exited with code [1-9].*")' 7d 50 \
  | jq -r '[.event_timestamp, .conversation_id[0:13], (.arguments | .[0:120]), .exit] | @tsv'
```

Codex tokens per session (input includes cached; Codex reports no cost):

```sh
for f in input cached output; do
  q loki /loki/api/v1/query query="sum by (attributes_conversation_id, attributes_model) (sum_over_time({job=~\"codex.*|T3 Code\"} |= \"response.completed\" | json | attributes_event_kind=\"response.completed\" | attributes_input_token_count!=\"\" | unwrap attributes_${f}_token_count [7d]))" \
    | jq -r --arg f $f '.data.result[] | [.metric.attributes_conversation_id, .metric.attributes_model, $f, .value[1]] | @tsv'
done
```

Trace to events and back: every Claude event carries its prompt's `traceid`, and a prompt's events share `prompt_id`.

```sh
T=<traceid>
q events "{job=\"claude-code\"} |= \"$T\" | json | traceid=\"$T\"" 7d | jq -r '[.event_timestamp, .event_name, .tool_name // "", .success // "", .cost_usd // ""] | @tsv'
q tempo /api/v2/traces/$T | jq -r '[.trace.resourceSpans[].scopeSpans[].spans[] | {name, d: (((.endTimeUnixNano | tonumber) - (.startTimeUnixNano | tonumber)) / 1e9)}] | group_by(.name)[] | [.[0].name, length, (map(.d) | add)] | @tsv'
```
