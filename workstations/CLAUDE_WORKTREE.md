# Claude Worktree Workflow

## Quick Start

The `claude-worktree` command (alias: `cwt`) helps you manage git worktrees for Claude development.

### Create a Worktree

```bash
# Create new worktree or checkout existing branch
cwt my-feature

# Create new branch from a different base
cwt my-feature --from origin/dev

# Checkout existing remote branch
cwt existing-feature

# Create without opening Ghostty
cwt my-feature --no-open
```

#### Intelligent Branch Detection

The script automatically detects existing branches:

1. **Local branch exists** → Checks it out in the worktree
2. **Remote branch exists** (e.g., `origin/my-feature`) → Creates local tracking branch
3. **Neither exists** → Creates new branch from base (default: `origin/main`, or use `--from`)

This allows you to:

- Continue work on existing feature branches
- Pull down branches from remote to work on them
- Create fresh branches for new features

#### What Happens

1. Fetch latest changes from origin
2. Check for existing branch (local or remote)
3. Create or checkout the branch in `.claude/worktrees/<name>`
4. Copy your `.env` file to the new worktree (if it exists)
5. Auto-detect your package manager and run the appropriate install command:
   - `bun install` for bun.lockb
   - `pnpm install` for pnpm-lock.yaml
   - `yarn install` for yarn.lock
   - `npm install` for package-lock.json or package.json
   - `cargo build` for Cargo.lock
   - `go mod download` for go.mod
   - `pip install -r requirements.txt` for requirements.txt
   - `pipenv install` for Pipfile.lock
6. **Open a new Ghostty window** in the worktree directory (unless `--no-open` is specified)

### List Worktrees

```bash
# List all active Claude worktrees
cwt list

# Short alias
cwt ls
```

Shows all worktrees in `.claude/worktrees/` with their branch names and detects orphaned directories.

### Close/Remove a Worktree

```bash
# Remove a worktree
cwt close my-feature

# Aliases also work
cwt remove my-feature
cwt rm my-feature
```

This will:

- Remove the worktree directory
- Optionally prompt to delete the associated branch

### Options

**Create command:**

- `--from <branch>` - Base branch to create from (default: `origin/main`, only used for NEW branches)
- `--no-open` - Skip opening a new Ghostty window

## Example Workflows

### Starting a New Feature

```bash
# Create a new feature branch from main
cwt add-dark-mode
# → Creates new branch 'add-dark-mode' from origin/main
# → Status: Created new branch from origin/main
```

### Working on Existing Feature

```bash
# Someone pushed a branch you want to work on
cwt fix-auth-bug
# → Finds origin/fix-auth-bug, creates local tracking branch
# → Status: Checked out existing remote branch (now tracking)
```

### Continue Working on Local Branch

```bash
# You already have a local branch but want it in a worktree
cwt refactor-api
# → Checks out your existing local branch
# → Status: Checked out existing local branch
```

### Creating from Different Base

```bash
# Create a hotfix from production branch
cwt urgent-fix --from origin/production
# → Creates new branch from origin/production instead of origin/main
# → Status: Created new branch from origin/production
```

## Command Reference

### Full Command List

```bash
cwt <name> [--from <branch>] [--no-open]  # Create worktree (default)
cwt list                                   # List all worktrees
cwt close <name>                          # Remove worktree
cwt help                                  # Show help
```

### Manual Git Commands

You can also use git directly if needed:

```bash
# List all git worktrees (not just Claude ones)
git worktree list

# Manually remove a worktree
git worktree remove .claude/worktrees/my-feature --force
```

## Claude Code Installation

This configuration supports Claude Code on both macOS and NixOS/Linux:

### macOS Installation

Claude Code is installed via Homebrew Cask (defined in `modules/darwin/homebrew.nix:33`):

```nix
casks = [
  # ...
  "claude-code"
];
```

Benefits:

- Automatic updates via Homebrew
- Official distribution method from Anthropic
- Native macOS integration

### NixOS/Linux Installation

Claude Code is installed via the [sadjow/claude-code-nix](https://github.com/sadjow/claude-code-nix) flake for automatic updates.

Configuration in `flake.nix`:

```nix
inputs = {
  claude-code-nix = {
    url = "github:sadjow/claude-code-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

Usage in `modules/home/agents/packages.nix`:

```nix
home.packages = with pkgs; [
  # ...
]
++ lib.optionals (!isDarwin) [
  claude-code-nix.packages.${pkgs.system}.default
];
```

Benefits:

- **Hourly automatic updates** - New releases available within ~1 hour
- Uses native binary (self-contained, no runtime dependencies)
- Declarative installation
- Reproducible across machines
- Alternative variants available: Node.js and Bun versions

To use a different variant (Node.js or Bun), change `default` to `nodejs` or `bun`:

```nix
claude-code-nix.packages.${pkgs.system}.nodejs  # Node.js version
claude-code-nix.packages.${pkgs.system}.bun     # Bun version
```

### Ghostty Terminal Installation

Ghostty is installed on both platforms for the integrated workflow:

**macOS**: Installed via Homebrew Cask (`modules/darwin/homebrew.nix:24`)

```nix
casks = [
  "ghostty"
];
```

**NixOS/Linux**: Installed via nixpkgs (`modules/home/agents/packages.nix`)

```nix
++ lib.optionals (!isDarwin) [
  ghostty
];
```

The worktree script automatically:

- Detects if Ghostty is available
- Opens a new Ghostty window in the worktree directory
- Falls back gracefully if Ghostty isn't installed

### Development Installation

The worktree script is installed as a Nix package in `modules/home/agents/scripts.nix`, making it:

- Available in your PATH automatically
- Reproducible across machines
- Managed declaratively with your other packages

## Implementation Notes

### Why Shell Script?

The tool is implemented in Bash because:

- **No build step required** - Works immediately after installation
- **Portable** - Runs anywhere with bash (macOS, Linux, etc.)
- **Fits Nix ecosystem** - Easy to package with `writeShellScriptBin`
- **Simple dependencies** - Only requires git, bash, and optional package managers
- **Fast execution** - No runtime startup cost like Node.js or compiled languages

The script is organized with functions and clear separation of concerns, making it maintainable even as complexity grows. For much more complex tooling, consider Rust or TypeScript, but for this workflow automation, shell script is ideal.
