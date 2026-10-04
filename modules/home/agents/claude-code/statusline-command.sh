#!/usr/bin/env bash
# Claude Code status line - agnoster-style prompt
input=$(cat)

cwd=$(echo "$input" | jq -r '.cwd')
model=$(echo "$input" | jq -r '.model.display_name')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
cost_usd=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')

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
	# Squish long branch names: first/.../last
	IFS='/' read -ra bparts <<<"$git_branch_raw"
	if [ "${#bparts[@]}" -gt 2 ]; then
		git_branch_raw="${bparts[0]}/.../$(
			IFS='/'
			echo "${bparts[*]:${#bparts[@]}-1}"
		)"
	fi
	git_branch="  $git_branch_raw"
fi

# Context usage
ctx_info=""
if [ -n "$used_pct" ]; then
	ctx_info=" [ctx: ${used_pct}%]"
fi

# Session cost
cost_info=""
if [ -n "$cost_usd" ]; then
	cost_info=$(printf ' [$%.2f]' "$cost_usd")
fi

printf "\033[34m%s\033[0m\033[33m%s\033[0m\n\033[32m%s\033[0m%s%s" \
	"$short_cwd" \
	"$git_branch" \
	"$model" \
	"$ctx_info" \
	"$cost_info"
