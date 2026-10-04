#!/usr/bin/env bash
# Claude worktree workflow script
# Manages git worktrees for Claude development workflow

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
usage() {
	cat <<EOF
Usage: claude-worktree <command> [options]

Commands:
  <name>              Create worktree or checkout existing branch (default command)
  list                List all active worktrees
  close <name>        Remove/delete a worktree

Create Options:
  --from <branch>     Base branch to create worktree from (default: origin/main)
                      Only used when creating a NEW branch
  --no-open          Don't open a new terminal after creation
  --no-dev           Don't launch the repo dev stack/tabs (dev is the default)

Branch Behavior:
  The script intelligently handles existing branches:
  - If local branch exists: checks it out
  - If remote branch exists: creates tracking branch
  - If neither exists: creates new branch from --from option (default: origin/main)

Examples:
  cwt my-feature                    # Auto-detect or create, open in cmux/Ghostty
  cwt my-feature --from origin/dev  # Create NEW branch from origin/dev
  cwt existing-branch               # Checkout existing branch in worktree
  cwt my-feature --no-open          # Create/checkout without opening terminal
  cwt list                          # List all worktrees
  cwt close my-feature              # Remove my-feature worktree
EOF
	exit 1
}

# Get repository root
get_repo_root() {
	local root
	root=$(git rev-parse --show-toplevel 2>/dev/null || true)
	if [[ -z "$root" ]]; then
		log_error "Not in a git repository"
		exit 1
	fi
	echo "$root"
}

# List all worktrees in .claude/worktrees
cmd_list() {
	local repo_root
	repo_root=$(get_repo_root)
	local worktrees_dir="$repo_root/.claude/worktrees"

	if [[ ! -d "$worktrees_dir" ]]; then
		log_info "No worktrees directory found"
		echo "Run 'cwt <name>' to create your first worktree"
		return 0
	fi

	log_info "Active Claude worktrees:"
	echo ""

	# Use git worktree list and filter for .claude/worktrees
	if git worktree list | grep -q ".claude/worktrees"; then
		git worktree list | grep ".claude/worktrees" | while IFS= read -r line; do
			# Extract just the worktree name from the path
			local worktree_path
			worktree_path=$(echo "$line" | awk '{print $1}')
			local worktree_name
			worktree_name=$(basename "$worktree_path")
			local branch
			# Extract branch name from brackets [branch-name]
			branch=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
			[[ -z "$branch" ]] && branch="detached"
			echo -e "  ${BLUE}•${NC} ${GREEN}$worktree_name${NC} ${YELLOW}[$branch]${NC}"
		done
	else
		echo "  No active worktrees found"
	fi

	echo ""
	# Also show directories that might not be tracked by git
	local orphaned=false
	shopt -s nullglob
	for dir in "$worktrees_dir"/*; do
		if [[ -d "$dir" ]]; then
			local dir_name
			dir_name=$(basename "$dir")
			if ! git worktree list | grep -q "$dir_name"; then
				if [[ "$orphaned" == false ]]; then
					log_warn "Orphaned directories (not tracked by git):"
					orphaned=true
				fi
				echo -e "  ${YELLOW}•${NC} $dir_name ${RED}[orphaned - use 'rm -rf' to remove]${NC}"
			fi
		fi
	done
	shopt -u nullglob
}

# Close/remove a worktree
cmd_close() {
	if [[ $# -ne 1 ]]; then
		log_error "Usage: cwt close <name>"
		exit 1
	fi

	local worktree_name="$1"
	local repo_root
	repo_root=$(get_repo_root)
	local worktree_dir="$repo_root/.claude/worktrees/$worktree_name"

	if [[ ! -d "$worktree_dir" ]]; then
		log_error "Worktree '$worktree_name' not found at: $worktree_dir"
		exit 1
	fi

	# Safety: resolve real path and ensure it's inside .claude/worktrees/
	local real_path expected_parent
	real_path=$(cd "$worktree_dir" && pwd -P)
	expected_parent=$(cd "$repo_root/.claude/worktrees" && pwd -P)
	if [[ "$real_path" != "$expected_parent"/* ]]; then
		log_error "Resolved path '$real_path' is outside '$expected_parent' — aborting"
		exit 1
	fi

	log_info "Removing worktree: $worktree_name"

	# Check for uncommitted changes (refresh first so files that differ only by
	# stat/mtime, not content, are not reported as changed).
	git -C "$worktree_dir" update-index -q --refresh >/dev/null 2>&1 || true
	if ! git -C "$worktree_dir" diff-index --quiet HEAD 2>/dev/null || ! git -C "$worktree_dir" diff-files --quiet 2>/dev/null; then
		log_warn "Worktree has uncommitted changes that will be discarded"
		read -p "Continue with removal? [y/N] " -n 1 -r
		echo
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			log_info "Removal cancelled"
			return 0
		fi
	fi

	# Run the repository's worktree teardown hook if present, before anything is
	# removed (the worktree's docker/ must still exist). Keeps cwt
	# project-agnostic: repo-specific teardown (e.g. docker compose down -v of a
	# per-worktree dev stack) lives in the repo's own .claude/worktree-hooks.sh.
	local worktree_hook="$repo_root/.claude/worktree-hooks.sh"
	if [[ -f "$worktree_hook" ]]; then
		log_info "Running repo worktree teardown hook..."
		CWT_WORKTREE_DIR="$worktree_dir" \
			CWT_WORKTREE_NAME="$worktree_name" \
			CWT_REPO_ROOT="$repo_root" \
			bash "$worktree_hook" teardown || log_warn "worktree teardown hook exited non-zero"
	fi

	# Move bulky untracked dirs (node_modules in every workspace, build caches)
	# to a same-volume trash via instant renames, then delete them in the
	# background. git worktree remove then only deletes the small source tree,
	# so close returns fast instead of unlinking hundreds of thousands of files.
	local trash i=0 bulky extra
	trash="$(mktemp -d "$repo_root/.claude/worktrees/.cwt-trash-XXXXXX" 2>/dev/null || true)"
	if [[ -n "$trash" && -d "$trash" ]]; then
		while IFS= read -r -d '' bulky; do
			mv "$bulky" "$trash/$i" 2>/dev/null && i=$((i + 1)) || true
		done < <(find "$worktree_dir" \
			-type d \( -name node_modules -o -name target -o -name .next -o -name dist \) -prune -print0 2>/dev/null)
		for extra in .yarn/cache .yarn/unplugged; do
			if [[ -d "$worktree_dir/$extra" ]]; then
				mv "$worktree_dir/$extra" "$trash/$i" 2>/dev/null && i=$((i + 1)) || true
			fi
		done
		if [[ "$i" -gt 0 ]]; then
			nohup rm -rf "$trash" >/dev/null 2>&1 &
		else
			rmdir "$trash" 2>/dev/null || true
		fi
	fi

	# Remove the worktree (--force to handle uncommitted changes)
	if git worktree remove "$worktree_dir" --force 2>/dev/null; then
		log_info "Worktree removed successfully"
	else
		# If git worktree remove fails, try manual cleanup
		log_warn "Git worktree remove failed, cleaning up manually..."
		rm -rf "$worktree_dir"
		git worktree prune
		log_info "Directory removed"
	fi

	# Optionally delete the branch if it exists and matches the worktree name
	if git show-ref --verify --quiet "refs/heads/$worktree_name"; then
		read -p "Delete branch '$worktree_name' as well? [y/N] " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			git branch -D "$worktree_name"
			log_info "Branch '$worktree_name' deleted"
		fi
	fi
}

# Seed a new worktree's dependencies and build artifacts from a source checkout
# via APFS clonefile(2) on each directory: one fast kernel-side syscall per tree,
# unlike `cp -cR` which clones per file and crawls for minutes on a node_modules
# with hundreds of thousands of small files. The package install then verifies
# instead of re-downloading and rebuilding. macOS + python3 only; best-effort.
seed_dev_artifacts() {
	local source_dir="$1"
	local worktree_dir="$2"

	[[ "$OSTYPE" == "darwin"* ]] || return 0
	# python3 is used to call clonefile(2) directly. Without it, skip seeding and
	# let the install do its normal full work (cp -cR would be slower than that).
	command -v python3 >/dev/null 2>&1 || return 0

	log_info "Seeding deps from source via APFS clone..."
	local start=$SECONDS

	# Sources: node_modules trees (root + each workspace) plus package-manager
	# caches / build state, so the install can skip fetch and rebuild.
	local -a srcs=()
	local nm artifact
	while IFS= read -r -d '' nm; do
		srcs+=("$nm")
	done < <(find "$source_dir" \
		-path "$source_dir/.git" -prune -o \
		-path "$source_dir/.claude" -prune -o \
		-type d -name node_modules -prune -print0 2>/dev/null)
	for artifact in .yarn/cache .yarn/unplugged .yarn/build-state.yml .yarn/install-state.gz .pnp.cjs .pnp.loader.mjs; do
		if [[ -e "$source_dir/$artifact" ]]; then
			srcs+=("$source_dir/$artifact")
		fi
	done
	[[ ${#srcs[@]} -gt 0 ]] || return 0

	# Clone each source to its matching path under the worktree (skips any that
	# already exist; clonefile recreates the directory tree).
	local count
	count=$(
		python3 - "$source_dir" "$worktree_dir" "${srcs[@]}" <<'PY' 2>/dev/null
import ctypes, os, sys

libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
clonefile = libc.clonefile
clonefile.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32]
clonefile.restype = ctypes.c_int

src_root = sys.argv[1].rstrip("/") + "/"
dst_root = sys.argv[2]
n = 0
for src in sys.argv[3:]:
    rel = src[len(src_root):] if src.startswith(src_root) else os.path.basename(src)
    dst = os.path.join(dst_root, rel)
    if os.path.exists(dst):
        continue
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if clonefile(src.encode(), dst.encode(), 0) == 0:
        n += 1
print(n)
PY
	) || count=0

	log_info "Seeded ${count:-0} dep dir(s) in $((SECONDS - start))s; install will verify."
	return 0
}

# Detect package manager and install dependencies
install_dependencies() {
	local worktree_dir="$1"

	log_info "Detecting package manager..."

	if [[ -f "$worktree_dir/bun.lockb" ]]; then
		if command -v bun &>/dev/null; then
			log_info "Found bun.lockb, running bun install..."
			bun install
		else
			log_warn "Found bun.lockb but 'bun' command not found, skipping install"
		fi
	elif [[ -f "$worktree_dir/pnpm-lock.yaml" ]]; then
		if command -v pnpm &>/dev/null; then
			log_info "Found pnpm-lock.yaml, running pnpm install..."
			pnpm install
		else
			log_warn "Found pnpm-lock.yaml but 'pnpm' command not found, skipping install"
		fi
	elif [[ -f "$worktree_dir/yarn.lock" ]]; then
		if command -v yarn &>/dev/null; then
			log_info "Found yarn.lock, running yarn install..."
			yarn install
		else
			log_warn "Found yarn.lock but 'yarn' command not found, skipping install"
		fi
	elif [[ -f "$worktree_dir/package-lock.json" ]]; then
		if command -v npm &>/dev/null; then
			log_info "Found package-lock.json, running npm install..."
			npm install
		else
			log_warn "Found package-lock.json but 'npm' command not found, skipping install"
		fi
	elif [[ -f "$worktree_dir/package.json" ]]; then
		if command -v npm &>/dev/null; then
			log_warn "Found package.json but no lockfile, running npm install..."
			npm install
		else
			log_warn "Found package.json but 'npm' command not found, skipping install"
		fi
	elif [[ -f "$worktree_dir/Cargo.lock" ]]; then
		if command -v cargo &>/dev/null; then
			log_info "Found Cargo.lock, running cargo fetch..."
			cargo fetch
		else
			log_warn "Found Cargo.lock but 'cargo' command not found, skipping fetch"
		fi
	elif [[ -f "$worktree_dir/go.mod" ]]; then
		if command -v go &>/dev/null; then
			log_info "Found go.mod, running go mod download..."
			go mod download
		else
			log_warn "Found go.mod but 'go' command not found, skipping download"
		fi
	elif [[ -f "$worktree_dir/requirements.txt" ]]; then
		if command -v pip &>/dev/null; then
			log_warn "Found requirements.txt, running pip install (consider using a virtualenv)..."
			pip install -r requirements.txt
		else
			log_warn "Found requirements.txt but 'pip' command not found, skipping install"
		fi
	elif [[ -f "$worktree_dir/Pipfile.lock" ]]; then
		if command -v pipenv &>/dev/null; then
			log_info "Found Pipfile.lock, running pipenv install..."
			pipenv install
		else
			log_warn "Found Pipfile.lock but 'pipenv' command not found, skipping install"
		fi
	else
		log_warn "No recognized package manager lockfile found"
	fi
}

# Open terminal (cmux workspace if running, otherwise Ghostty window)
open_terminal() {
	local worktree_dir="$1"

	# Prefer cmux if we're inside a cmux terminal (CMUX_WORKSPACE_ID is set by cmux)
	if [[ -n "${CMUX_WORKSPACE_ID:-}" ]] && command -v cmux &>/dev/null; then
		log_info "Opening new cmux workspace..."
		cmux workspace create --cwd "$worktree_dir"
		echo -e "${GREEN}New cmux workspace opened${NC}"
		return
	fi

	if command -v ghostty &>/dev/null; then
		log_info "Opening new Ghostty window..."
		if [[ "$OSTYPE" == "darwin"* ]]; then
			# macOS: Use open command to launch Ghostty
			open -na Ghostty --args --working-directory="$worktree_dir" --window-save-state=never
		else
			# Linux: Launch Ghostty directly in background
			nohup ghostty --working-directory="$worktree_dir" &>/dev/null &
		fi
		echo -e "${GREEN}New Ghostty window opened${NC}"
	else
		log_warn "No terminal (cmux/Ghostty) found, skipping window open"
		echo -e "${GREEN}Command to enter:${NC} cd $worktree_dir"
	fi
}

# Create a new worktree
cmd_create() {
	local worktree_name=""
	local base_branch="origin/main"
	local open_terminal=true
	local dev_mode=true

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--from)
			base_branch="$2"
			shift 2
			;;
		--no-open)
			open_terminal=false
			shift
			;;
		--no-dev)
			dev_mode=false
			shift
			;;
		-*)
			log_error "Unknown option: $1"
			usage
			;;
		*)
			if [ -z "$worktree_name" ]; then
				worktree_name="$1"
			else
				log_error "Too many arguments"
				usage
			fi
			shift
			;;
		esac
	done

	# Validate worktree name
	if [[ -z "$worktree_name" ]]; then
		log_error "Worktree name is required"
		usage
	fi

	local repo_root
	repo_root=$(get_repo_root)
	local worktree_dir="$repo_root/.claude/worktrees/$worktree_name"

	# If worktree already exists, just open it
	if [[ -d "$worktree_dir" ]]; then
		log_info "Worktree already exists: $worktree_dir"
		if [[ "$open_terminal" == true ]]; then
			open_terminal "$worktree_dir"
		else
			echo -e "${GREEN}Command to enter:${NC} cd $worktree_dir"
		fi
		return 0
	fi

	# Create .claude/worktrees directory if it doesn't exist
	log_info "Creating .claude/worktrees directory..."
	mkdir -p "$repo_root/.claude/worktrees"

	# Fetch latest changes from origin
	log_info "Fetching latest changes from origin..."
	git fetch origin || log_warn "Failed to fetch from origin, continuing anyway..."

	# Check if branch already exists (local or remote)
	local branch_exists_local=false
	local branch_exists_remote=false

	if git show-ref --verify --quiet "refs/heads/$worktree_name"; then
		branch_exists_local=true
		log_info "Found existing local branch: $worktree_name"
	elif git show-ref --verify --quiet "refs/remotes/origin/$worktree_name"; then
		branch_exists_remote=true
		log_info "Found existing remote branch: origin/$worktree_name"
	fi

	# Create the worktree, either from existing branch or create new
	if [[ "$branch_exists_local" == true ]]; then
		log_info "Checking out existing local branch '$worktree_name'..."
		git worktree add "$worktree_dir" "$worktree_name"
	elif [[ "$branch_exists_remote" == true ]]; then
		log_info "Creating local tracking branch for 'origin/$worktree_name'..."
		git worktree add "$worktree_dir" -b "$worktree_name" "origin/$worktree_name"
	else
		log_info "Creating new branch '$worktree_name' from $base_branch..."
		git worktree add -b "$worktree_name" "$worktree_dir" "$base_branch"
	fi

	# Copy .env files recursively (preserving directory structure)
	log_info "Looking for .env files to copy..."
	local env_found=false
	while IFS= read -r -d '' env_file; do
		local rel_path="${env_file#"$repo_root"/}"
		# Skip git-tracked env templates (.env.example, .env.testing): they're
		# already in the checkout, and copying them stat-dirties the worktree,
		# which makes `cwt close` warn about non-existent uncommitted changes.
		if git -C "$repo_root" ls-files --error-unmatch "$rel_path" >/dev/null 2>&1; then
			continue
		fi
		mkdir -p "$(dirname "$worktree_dir/$rel_path")"
		cp "$env_file" "$worktree_dir/$rel_path"
		log_info "  Copied $rel_path"
		env_found=true
	done < <(find "$repo_root" \
		-path "$repo_root/.git" -prune -o \
		-path "$repo_root/.claude/worktrees" -prune -o \
		-path "*/node_modules" -prune -o \
		\( -name ".env" -o -name ".env.*" \) -type f -print0)
	if [[ "$env_found" == false ]]; then
		log_warn "No .env files found"
	fi

	# Symlink .claude local settings (pre-approved commands, MCP config, etc.)
	log_info "Setting up .claude directory symlinks..."
	mkdir -p "$worktree_dir/.claude"

	# Symlink settings.local.json
	if [[ -f "$repo_root/.claude/settings.local.json" ]]; then
		log_info "  Symlinking .claude/settings.local.json..."
		ln -sf "$repo_root/.claude/settings.local.json" "$worktree_dir/.claude/settings.local.json"
	fi

	# Symlink mcp.json (MCP server configuration)
	if [[ -f "$repo_root/.claude/mcp.json" ]]; then
		log_info "  Symlinking .claude/mcp.json..."
		ln -sf "$repo_root/.claude/mcp.json" "$worktree_dir/.claude/mcp.json"
	fi

	# Symlink any other local config files in .claude/ (but not directories like worktrees/)
	for config_file in "$repo_root/.claude"/*.json "$repo_root/.claude"/*.local.*; do
		if [[ -f "$config_file" ]]; then
			local filename
			filename=$(basename "$config_file")
			# Skip if already symlinked above
			if [[ "$filename" != "settings.local.json" && "$filename" != "mcp.json" ]]; then
				if [[ ! -e "$worktree_dir/.claude/$filename" ]]; then
					log_info "  Symlinking .claude/$filename..."
					ln -sf "$config_file" "$worktree_dir/.claude/$filename"
				fi
			fi
		fi
	done

	# Symlink CLAUDE.local.md
	if [[ -f "$repo_root/CLAUDE.local.md" ]]; then
		log_info "  Symlinking CLAUDE.local.md..."
		ln -sf "$repo_root/CLAUDE.local.md" "$worktree_dir/CLAUDE.local.md"
	fi

	# Change to worktree directory for package installation
	cd "$worktree_dir"

	# Trust mise config in the new worktree if mise is in use. Project-agnostic:
	# the worktree is the same content as the already-trusted main checkout, so
	# this just avoids an interactive "trust?" prompt during install.
	if command -v mise &>/dev/null; then
		log_info "Trusting mise config in worktree..."
		mise trust >/dev/null 2>&1 || true
	fi

	# Seed deps + build artifacts from the source checkout via APFS clone, so the
	# install verifies instead of re-downloading and rebuilding (macOS/APFS only).
	seed_dev_artifacts "$repo_root" "$worktree_dir"

	# Install dependencies (non-fatal so a failed install doesn't abort cwt mid-setup)
	install_dependencies "$worktree_dir" || log_warn "Dependency install reported errors; continuing (worktree still usable, re-run install if needed)"

	# Run the repository's worktree lifecycle hooks if present. Keeps cwt
	# project-agnostic: repo-specific setup (per-worktree dev env) and the dev
	# launch (e.g. cmux tabs for the dev stack) live in the repo's own
	# .claude/worktree-hooks.sh, dispatched by event.
	local worktree_hook="$repo_root/.claude/worktree-hooks.sh"
	if [[ -f "$worktree_hook" ]]; then
		log_info "Running repo worktree setup hook..."
		CWT_WORKTREE_DIR="$worktree_dir" \
			CWT_WORKTREE_NAME="$worktree_name" \
			CWT_REPO_ROOT="$repo_root" \
			bash "$worktree_hook" setup || log_warn "worktree setup hook exited non-zero"

		# Dev stack/tabs are the default; --no-dev skips them. When the dev hook
		# opens its own tabs, skip cwt's fallback single terminal.
		if [[ "$dev_mode" == true ]]; then
			log_info "Launching dev stack (--no-dev to skip)..."
			if CWT_WORKTREE_DIR="$worktree_dir" \
				CWT_WORKTREE_NAME="$worktree_name" \
				CWT_REPO_ROOT="$repo_root" \
				bash "$worktree_hook" dev; then
				open_terminal=false
			else
				log_warn "worktree dev hook exited non-zero"
			fi
		fi
	fi

	echo ""
	log_info "Worktree created successfully!"
	echo -e "${GREEN}Location:${NC} $worktree_dir"
	echo -e "${GREEN}Branch:${NC} $worktree_name"

	if [[ "$branch_exists_local" == true ]]; then
		echo -e "${BLUE}Status:${NC} Checked out existing local branch"
	elif [[ "$branch_exists_remote" == true ]]; then
		echo -e "${BLUE}Status:${NC} Checked out existing remote branch (now tracking)"
	else
		echo -e "${BLUE}Status:${NC} Created new branch from $base_branch"
	fi

	# Open Ghostty if requested
	if [[ "$open_terminal" == true ]]; then
		open_terminal "$worktree_dir"
	else
		echo -e "${GREEN}Command to enter:${NC} cd $worktree_dir"
	fi
}

# Main command dispatcher
main() {
	if [[ $# -eq 0 ]]; then
		usage
	fi

	local command="$1"
	shift

	case "$command" in
	list | ls)
		cmd_list "$@"
		;;
	close | remove | rm)
		cmd_close "$@"
		;;
	help | --help | -h)
		usage
		;;
	-*)
		# Options without command, treat as create
		cmd_create "$command" "$@"
		;;
	*)
		# Default to create command
		cmd_create "$command" "$@"
		;;
	esac
}

main "$@"
