# PreToolUse hook on Bash: deny foreground calls whose timeout runs longer
# than the prompt cache (5 minutes in subagents, about an hour in the main
# loop), so the next turn does not rewrite the full context. Only subagent
# payloads include agent_id.
#
# Foreground calls stop at their tool timeout (BASH_DEFAULT_TIMEOUT_MS, or
# 2 minutes if unset) regardless of the command, so checking the timeout is
# enough.
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

reason="Blocked: foreground Bash timeout (${seconds}s) exceeds the ${limit}s limit. The prompt cache expires after ${lifetime}, forcing the next turn to rewrite the full context. Keep the timeout at or under ${limit}s (wait in bounded steps with \`timeout $((limit - 30)) <cmd>\`), or use run_in_background and poll or watch with Monitor."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
