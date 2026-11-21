# Turns Antigravity hook events into OTLP spans, since agy has no OTel export.
# One trace per turn, rooted at antigravity.interaction, with a child per tool
# call and per model invocation (which may span the tools it ran). A
# TRACEPARENT from T3 or a parent agent becomes the turn's parent. Prepended
# by Nix: endpoint, host, details.
#
# agy waits on every hook, so this always answers at once, sends in the
# background and never blocks a tool: PreToolUse defers to normal permissions.

event=$1
respond() {
  if [ "$event" = PreToolUse ]; then echo '{"decision":"allow"}'; else echo '{}'; fi
}
trap 'respond; exit 0' EXIT

input=$(cat)
now=$(date +%s%N)
field() { jq -r "$1 // empty" <<<"$input"; }
rand() { od -An -tx1 -N"$1" /dev/urandom | tr -d ' \n'; }

conversation=$(field .conversationId | tr -cd 'A-Za-z0-9-')
[ -n "$conversation" ] || exit 0
dir="${XDG_RUNTIME_DIR:-/tmp}/agy-otel-$(id -u)/$conversation"
mkdir -p "$dir"

# The first event of a turn opens it; noclobber keeps parallel hooks to one.
if [ ! -e "$dir/turn" ]; then
  trace=$(rand 16) parent=""
  if [[ ${TRACEPARENT:-} =~ ^00-([0-9a-f]{32})-([0-9a-f]{16})-[0-9a-f]{2}$ ]]; then
    trace=${BASH_REMATCH[1]} parent=${BASH_REMATCH[2]}
  fi
  workspace=$(field '.workspacePaths[0]')
  repo=""
  if [ -n "$workspace" ]; then
    remote=$(git -C "$workspace" remote get-url origin 2>/dev/null || true)
    repo=$(basename "${remote:-$(git -C "$workspace" rev-parse --show-toplevel 2>/dev/null || true)}" .git)
  fi
  (set -C; jq -n -c --arg trace "$trace" --arg span "$(rand 8)" --arg parent "$parent" \
    --arg start "$now" --arg workspace "$workspace" --arg repo "$repo" \
    --arg thread "${T3CODE_THREAD_ID:-}" '$ARGS.named' >"$dir/turn") 2>/dev/null || true
fi
turn=$(cat "$dir/turn")

# Error text when tool details are on, else only that it failed.
error_text() {
  if [ "$details" = true ]; then
    echo "${1:0:512}"
  elif [ -n "$1" ]; then
    echo failed
  fi
}

# send NAME PARENT_SPAN_ID START ATTRS_JSON [ERROR]
send() {
  if [ "$1" = antigravity.interaction ]; then span=$(jq -r .span <<<"$turn"); else span=$(rand 8); fi
  body=$(jq -n -c \
    --argjson turn "$turn" --arg name "$1" --arg parent "$2" --arg start "$3" \
    --arg end "$now" --argjson attrs "$4" --arg error "${5:-}" --arg span "$span" \
    --arg host "$host" --arg conversation "$conversation" --arg model "$(field .modelName)" '
    def kv: to_entries | map(select(.value != "" and .value != null)
      | {key, value: (if (.value | type) == "boolean" then {boolValue: .value}
          elif (.value | type) == "number" then {intValue: (.value | tostring)}
          else {stringValue: (.value | tostring)} end)});
    {resourceSpans: [{
      resource: {attributes: ({"service.name": "antigravity", "host.name": $host} | kv)},
      scopeSpans: [{scope: {name: "agy-otel-hook"}, spans: [{
        traceId: $turn.trace, spanId: $span, parentSpanId: $parent, name: $name,
        kind: 1, startTimeUnixNano: $start, endTimeUnixNano: $end,
        attributes: ({"session.id": $conversation, "model": $model,
          "vcs.repository.name": $turn.repo, "workspace.path": $turn.workspace,
          "t3.thread_id": $turn.thread} + $attrs | kv),
        status: (if $error == "" then {} else {code: 2, message: $error} end)
      }]}]
    }]}')
  curl -s --max-time 5 -H 'Content-Type: application/json' --data-binary "$body" \
    "$endpoint/v1/traces" </dev/null >/dev/null 2>&1 &
}

turnSpan=$(jq -r .span <<<"$turn")
case $event in
  PreToolUse | PreInvocation)
    if [ "$event" = PreToolUse ]; then key="tool-$(field .stepIdx)"; else key="llm-$(field .invocationNum)"; fi
    echo "$now" >"$dir/$key"
    ;;
  PostToolUse)
    key="tool-$(field .stepIdx)"
    start=$(cat "$dir/$key" 2>/dev/null || echo "$now")
    rm -f "$dir/$key"
    error=$(field .error)
    attrs=$(jq -c --argjson details "$details" --arg error "$error" '{
      tool_name: .toolCall.name,
      success: ($error == ""),
      tool_input: (if $details then (.toolCall.args | tojson | .[0:512]) else "" end)
    }' <<<"$input")
    send antigravity.tool "$turnSpan" "$start" "$attrs" "$(error_text "$error")"
    ;;
  PostInvocation)
    key="llm-$(field .invocationNum)"
    start=$(cat "$dir/$key" 2>/dev/null || echo "$now")
    rm -f "$dir/$key"
    send antigravity.invocation "$turnSpan" "$start" "$(jq -c '{invocation: .invocationNum}' <<<"$input")"
    ;;
  Stop)
    error=$(field .error)
    send antigravity.interaction "$(jq -r .parent <<<"$turn")" "$(jq -r .start <<<"$turn")" \
      "$(jq -c '{termination_reason: .terminationReason}' <<<"$input")" \
      "$(error_text "$error")"
    rm -rf "$dir"
    ;;
esac
