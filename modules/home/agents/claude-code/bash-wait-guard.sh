# PreToolUse hook on Bash: deny foreground calls whose timeout outlives the
# prompt cache. The next model call would then rewrite the whole context.
# Subagent caches last 5 minutes and the main loop's about an hour. Only
# subagent payloads carry agent_id.
#
# A foreground call ends at its tool timeout (default BASH_DEFAULT_TIMEOUT_MS,
# 2 minutes), whatever the command, so the timeout alone bounds the wait.
input=$(cat)

read -r background agent timeout < <(
  jq -r '[
    .tool_input.run_in_background // false,
    (if .agent_id then "subagent" else "main" end),
    .tool_input.timeout // ""
  ] | @tsv' <<<"$input"
) || exit 0

[ "$background" = true ] && exit 0

if [ "$agent" = subagent ]; then
  limit=270
  lifetime="5 minutes in a subagent"
else
  limit=3300
  lifetime="about an hour"
fi

timeout_ms=${timeout:-${BASH_DEFAULT_TIMEOUT_MS:-120000}}
[[ $timeout_ms =~ ^[0-9]+$ ]] || exit 0
seconds=$((timeout_ms / 1000))
[ "$seconds" -le "$limit" ] && exit 0

reason="Blocked: a foreground Bash call of up to ${seconds}s outlives the prompt cache (${lifetime}), so the next turn would rewrite the whole context. Keep the timeout at or under ${limit}s: wait in bounded steps such as \`timeout $((limit - 30)) <wait>\` and check again, or start long work such as a build with run_in_background and poll its output or watch it with Monitor."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
