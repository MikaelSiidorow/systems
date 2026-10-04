#!/usr/bin/env bash
# Cursor Agent CLI status line - matches Claude Code agnoster-style layout
input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
param=$(echo "$input" | jq -r '.model.param_summary // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
worktree=$(echo "$input" | jq -r '.worktree.name // empty')

# Shorten home directory to ~
home="$HOME"
short_cwd="${cwd/#$home/\~}"

# Squish long paths: ~/first/.../last
IFS='/' read -ra parts <<<"$short_cwd"
if [ "${#parts[@]}" -gt 3 ]; then
	short_cwd="${parts[0]}/${parts[1]}/.../${parts[-1]}"
fi

# Get git branch (skip optional locks)
git_branch=""
if git_branch_raw=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null); then
	IFS='/' read -ra bparts <<<"$git_branch_raw"
	if [ "${#bparts[@]}" -gt 2 ]; then
		git_branch_raw="${bparts[0]}/.../${bparts[-1]}"
	fi
	git_branch="  $git_branch_raw"
fi

# Worktree badge (when cwd is a worktree)
wt_info=""
if [ -n "$worktree" ]; then
	wt_info="  [$worktree]"
fi

# Context usage (integer %)
ctx_info=""
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ]; then
	ctx_info=$(printf ' [ctx: %.0f%%]' "$used_pct")
fi

# Model params (e.g. Thinking) — skip if already in display_name
model_label="$model"
if [ -n "$param" ] && [[ "$model" != *"$param"* ]]; then
	model_label="$model $param"
fi

printf "\033[34m%s\033[0m\033[33m%s\033[0m\033[35m%s\033[0m\n\033[32m%s\033[0m%s" \
	"$short_cwd" \
	"$git_branch" \
	"$wt_info" \
	"$model_label" \
	"$ctx_info"
