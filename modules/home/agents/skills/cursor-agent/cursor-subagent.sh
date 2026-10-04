#!/usr/bin/env bash
# Run cursor-agent headless as a sub-agent, tracking each run so it can be
# listed, resumed, or cancelled later. State lives outside Nix (mutable runtime).
#
#   cursor-subagent.sh run [--name N] [--model M] [--write] [--worktree] -- <prompt...>
#   cursor-subagent.sh resume <name|chatId> [--model M] [--write] [--worktree] -- <prompt...>
#   cursor-subagent.sh list
#   cursor-subagent.sh cancel <name>
#
# Runs block until cursor-agent finishes; use Claude's background job control to
# run them asynchronously. Read-only (--plan) by default; --write allows edits.
# On resume, the tracked model is reused unless --model is passed.
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cursor-agent-subagent"
STATE_FILE="$STATE_DIR/jobs.json"

die() {
	echo "cursor-subagent: $*" >&2
	exit 1
}

command -v cursor-agent >/dev/null 2>&1 || die "cursor-agent not found on PATH"
command -v jq >/dev/null 2>&1 || die "jq not found on PATH"

mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '{"jobs":[]}' >"$STATE_FILE"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Replace (or insert) a job object, keyed by .name.
upsert() {
	local tmp
	tmp="$(mktemp)"
	jq --argjson j "$1" '.jobs |= (map(select(.name != $j.name)) + [$j])' \
		"$STATE_FILE" >"$tmp" && mv "$tmp" "$STATE_FILE"
}

field() { # name field -> value
	jq -r --arg n "$1" --arg f "$2" \
		'.jobs[] | select(.name==$n) | .[$f] // empty' "$STATE_FILE"
}

# cursor-agent --output-format json emits a single result object with the chat
# id in .session_id. Empty if a failed run produced no such object.
extract_chat_id() { jq -r '.session_id // empty' 2>/dev/null || true; }

# Launch cursor-agent with the given name and pre-built flag array (name, then
# flags). Blocks, records state before and after, prints raw output.
launch() {
	local name="$1" mode="$2" model="$3" sandbox="$4" prompt="$5"
	shift 5
	local out="$STATE_DIR/$name.out"
	local session="${CLAUDE_CODE_SESSION_ID:-}"

	cursor-agent "$@" "$prompt" >"$out" 2>&1 &
	local pid=$!
	# created_at is set once (preserved across resume); updated_at tracks activity.
	upsert "$(jq -n --slurpfile st "$STATE_FILE" \
		--arg n "$name" --arg pid "$pid" --arg model "$model" --arg mode "$mode" \
		--arg sandbox "$sandbox" --arg session "$session" \
		--arg cwd "$PWD" --arg t "$(now)" --arg p "${prompt:0:200}" \
		'{name:$n,status:"running",pid:($pid|tonumber),model:$model,mode:$mode,sandbox:$sandbox,session:$session,cwd:$cwd,
		  created_at:(($st[0].jobs | map(select(.name==$n)) | .[0].created_at) // $t),
		  updated_at:$t,prompt:$p,chatId:null,finished_at:null,exit:null}')"

	local rc=0
	wait "$pid" || rc=$?

	# cancel may have already marked this job; don't clobber that.
	[ "$(field "$name" status)" = "cancelled" ] && {
		cat "$out"
		return "$rc"
	}

	local chat status
	chat="$(extract_chat_id <"$out")"
	[ "$rc" -eq 0 ] && status="done" || status="failed"
	# merge into the running entry so created_at/prompt/etc. are preserved.
	upsert "$(jq -n --slurpfile st "$STATE_FILE" \
		--arg n "$name" --arg s "$status" --arg chat "$chat" \
		--arg t "$(now)" --arg rc "$rc" \
		'($st[0].jobs[] | select(.name==$n))
		 + {status:$s, pid:null, finished_at:$t, updated_at:$t, exit:($rc|tonumber),
		    chatId:(if $chat=="" then null else $chat end)}')"

	echo "cursor-subagent: [$name] $status (chatId: ${chat:-none})" >&2
	# Print the agent's text answer (.result); raw JSON stays in "$out".
	local text
	text="$(jq -r '.result // empty' "$out" 2>/dev/null || true)"
	if [ -n "$text" ]; then printf '%s\n' "$text"; else cat "$out"; fi
	return "$rc"
}

# Parse shared run/resume options, then run `launch`.
run_like() {
	local resume_ref="$1"
	shift
	local name="" model="" write=0 worktree=0 prompt=""
	while [ $# -gt 0 ]; do
		case "$1" in
		--name)
			name="$2"
			shift 2
			;;
		--model)
			model="$2"
			shift 2
			;;
		--write)
			write=1
			shift
			;;
		--worktree)
			worktree=1
			shift
			;;
		--)
			shift
			prompt="$*"
			break
			;;
		*)
			prompt="$*"
			break
			;;
		esac
	done
	[ -n "$prompt" ] || die "no prompt given"

	if [ -n "$resume_ref" ]; then
		local chat
		chat="$(field "$resume_ref" chatId)"
		[ -n "$chat" ] || chat="$resume_ref" # allow a raw chatId
		[ -n "$chat" ] || die "no chatId for '$resume_ref'"
		[ -n "$name" ] || name="$resume_ref"
		# Reuse the tracked model unless the caller passed --model (keeps
		# prompt cache warm across turns in the same session).
		if [ -z "$model" ]; then
			model="$(field "$resume_ref" model)"
			if [ -z "$model" ]; then
				model="$(jq -r --arg c "$chat" \
					'.jobs[] | select(.chatId==$c) | .model // empty' "$STATE_FILE" |
					head -n1)"
			fi
		fi
	fi
	[ -n "$name" ] || name="cx-$(date +%s)"

	# Sandbox is always on: the agent's commands are confined to the workspace
	# for writes and denied network by default. (Agent mode exposes no
	# blocked-patterns, so a .env inside the workspace stays readable.)
	local flags=(-p --output-format json --trust --sandbox enabled)
	local mode="plan"
	if [ "$write" -eq 1 ]; then
		flags+=(--force)
		mode="write"
	else
		flags+=(--plan)
	fi
	[ -n "$model" ] && flags+=(--model "$model")
	# cursor-agent's worktree option has an optional value. Passing it bare before
	# the positional prompt makes its argument parser consume the prompt as the
	# worktree name, so bind the tracked run name explicitly with `=`.
	[ "$worktree" -eq 1 ] && flags+=("--worktree=$name")
	[ -n "$resume_ref" ] && flags+=(--resume "$chat")

	launch "$name" "$mode" "$model" "enabled" "$prompt" "${flags[@]}"
}

cmd_list() {
	printf 'STATUS\tNAME\tMODE\tMODEL\tCHATID\tCREATED\tUPDATED\n'
	jq -r '.jobs | sort_by(.updated_at) | reverse[]
	       | [.status, .name, .mode, (.model // "-"), (.chatId // "-"), (.created_at // "-"), (.updated_at // "-")]
	       | @tsv' "$STATE_FILE"
}

cmd_cancel() {
	local name="${1:-}"
	[ -n "$name" ] || die "usage: cancel <name>"
	local pid
	pid="$(field "$name" pid)"
	[ -n "$pid" ] || die "no running job named '$name'"
	kill "$pid" 2>/dev/null || true
	upsert "$(jq -n --slurpfile st "$STATE_FILE" --arg n "$name" \
		'($st[0].jobs[] | select(.name==$n)) + {status:"cancelled", pid:null}')"
	echo "cursor-subagent: cancelled $name" >&2
}

case "${1:-}" in
run)
	shift
	run_like "" "$@"
	;;
resume)
	shift
	[ $# -ge 1 ] || die "usage: resume <name|chatId> -- <prompt>"
	ref="$1"
	shift
	run_like "$ref" "$@"
	;;
list)
	cmd_list
	;;
cancel)
	shift
	cmd_cancel "$@"
	;;
*)
	die "usage: {run|resume|list|cancel} ..."
	;;
esac
