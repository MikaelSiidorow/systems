# PreToolUse hook on Bash: deny foreground calls whose timeout runs longer
# than the prompt cache (5 minutes in subagents, about an hour in the main
# loop), so the next turn does not rewrite the full context. Only subagent
# payloads include agent_id.
#
# Foreground calls stop at their tool timeout (BASH_DEFAULT_TIMEOUT_MS, or
# 2 minutes if unset) regardless of the command, so checking the timeout is
# enough.
input=$(cat)

# Resolve the timeout the way Claude Code does: a missing or zero timeout
# takes the default, and BASH_MAX_TIMEOUT_MS caps it. Numbers may arrive as
# strings or fractions, so jq parses them and rounds up to whole ms.
read -r background agent timeout_ms < <(
  jq -r --arg default "${BASH_DEFAULT_TIMEOUT_MS:-}" --arg max "${BASH_MAX_TIMEOUT_MS:-}" '
    def ms($fallback):
      (if type == "number" then . else tonumber? end // 0) as $n
      | if $n > 0 then $n else $fallback end;
    ($max | ms(600000)) as $cap
    | ($default | ms(120000)) as $fallback
    | [
        (.tool_input.run_in_background // false | tostring),
        (if .agent_id then "subagent" else "main" end),
        ([(.tool_input.timeout | ms($fallback)), $cap] | min | ceil)
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

[[ $timeout_ms =~ ^[0-9]+$ ]] || exit 0
[ "$timeout_ms" -le $((limit * 1000)) ] && exit 0
seconds=$(((timeout_ms + 999) / 1000))

reason="Blocked: foreground Bash timeout (${seconds}s) exceeds the ${limit}s limit. The prompt cache expires after ${lifetime}, forcing the next turn to rewrite the full context. Keep the timeout at or under ${limit}s (wait in bounded steps with \`timeout $((limit - 30)) <cmd>\`), or use run_in_background and poll or watch with Monitor."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
