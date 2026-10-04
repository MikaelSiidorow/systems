# Multi-host Nix configuration Makefile
# Supports nix-darwin (macOS) and home-manager (Linux standalone)

# Detect platform
HOSTNAME := $(shell hostname -s)
UNAME := $(shell uname -s)
# Shared home-manager modules in ../modules are checked along with this flake.
SHELL_SOURCES := $(shell git ls-files '*.sh' '*.bash') \
	$(addprefix ../modules/,$(shell git -C ../modules ls-files '*.sh' '*.bash' ':!home/agents/skills/**'))
CHECK_SHELL := nix develop .\#checks -c

# darwin-rebuild auto-resolves darwinConfigurations.$(scutil --get LocalHostName)
# when no flake attr is specified, so we pass `.` and let it pick.
# home-manager has no equivalent default, so we pass the full target.
ifeq ($(UNAME),Darwin)
	HOSTNAME := $(shell scutil --get LocalHostName)
	DARWIN_REBUILD := $(shell command -v darwin-rebuild 2>/dev/null || true)
	ifeq ($(DARWIN_REBUILD),)
		BUILD_CMD := nix run .\#darwin-rebuild --
	else
		BUILD_CMD := sudo darwin-rebuild
	endif
	FLAKE_TARGET := .
	DISPLAY_TARGET := darwinConfigurations.$(HOSTNAME)
	SWITCH_FLAGS :=
	HOST_KIND := darwin
else ifeq ($(HOSTNAME),nixos-laptop)
	BUILD_CMD := sudo nixos-rebuild
	FLAKE_TARGET := .\#nixos-laptop
	DISPLAY_TARGET := nixosConfigurations.nixos-laptop
	SWITCH_FLAGS :=
	HOST_KIND := nixos
else
	HOME_MANAGER := $(shell command -v home-manager 2>/dev/null || true)
	ifeq ($(HOME_MANAGER),)
		BUILD_CMD := nix run .\#home-manager --
	else
		BUILD_CMD := home-manager
	endif
	FLAKE_TARGET := .\#mikaelsiidorow@tpad
	DISPLAY_TARGET := $(FLAKE_TARGET)
	SWITCH_FLAGS := -b backup
	HOST_KIND := home
endif

# Default target - show help
.PHONY: help
help:
	@echo "Nix Configuration Management"
	@echo ""
	@echo "Detected: $(HOSTNAME) ($(UNAME))"
	@echo "Target: $(DISPLAY_TARGET)"
	@echo ""
	@echo "Common targets:"
	@echo "  make switch       - Build and activate configuration for current host"
	@echo "  make build        - Build configuration without activating"
	@echo "  make check        - Check formatting, lint, and flake outputs"
	@echo "  make update       - Update flake inputs"
	@echo "  make update-fast  - Update fast-moving app inputs"
	@echo "  make upgrade      - Update inputs and switch"
	@echo "  make brew-upgrade - Update Homebrew packages on macOS"
	@echo "  make clean        - Run garbage collection"
	@echo "  make fmt          - Format supported repository files"
	@echo ""
	@echo "Other targets:"
	@echo "  make format-check - Check formatting without activating"
	@echo "  make lint         - Run ShellCheck, deadnix, and statix"
	@echo "  make plasma-vm    - Build and launch the NixOS Plasma preview"
	@echo "  make tpad         - Build and activate the ThinkPad (Pop!_OS) configuration"
	@echo "  make diff         - Show what would change"
	@echo "  make history      - Show system generations"
	@echo "  make rollback     - Rollback to previous generation"

# Auto-detected switch
.PHONY: switch
switch:
	@echo "Building $(DISPLAY_TARGET)..."
	$(BUILD_CMD) switch $(SWITCH_FLAGS) --flake $(FLAKE_TARGET)

# Build without activating
.PHONY: build
build:
	@echo "Building $(DISPLAY_TARGET)..."
	$(BUILD_CMD) build --flake $(FLAKE_TARGET)

# Check formatting in treefmt's CI mode
.PHONY: format-check
format-check:
	$(CHECK_SHELL) treefmt --config-file home/treefmt.toml --tree-root . --ci
	$(CHECK_SHELL) treefmt --config-file home/treefmt.toml --tree-root ../modules --ci

# Lint shell and Nix sources
.PHONY: lint
lint:
	$(CHECK_SHELL) shellcheck $(SHELL_SOURCES)
	$(CHECK_SHELL) deadnix --fail . ../modules
	$(CHECK_SHELL) statix check .
	$(CHECK_SHELL) statix check ../modules

# Check formatting, lint, and flake outputs
.PHONY: check
check: format-check lint
	nix flake check

# Show what would change (dry-run)
.PHONY: diff
diff:
	@echo "Checking changes for $(DISPLAY_TARGET)..."
ifneq ($(HOST_KIND),home)
	$(BUILD_CMD) build --flake $(FLAKE_TARGET)
	nix store diff-closures /run/current-system ./result
else
	home-manager build --flake $(FLAKE_TARGET)
	nix store diff-closures ~/.local/state/nix/profiles/home-manager ./result
endif

# Update flake inputs
.PHONY: update
update:
	nix flake update

# Update fast-moving desktop inputs without moving the default stable package set
.PHONY: update-fast
update-fast:
	nix flake update \
		nixpkgs-unstable \
		nur \
		nix-index-database \
		claude-code-nix \
		codex-cli-nix \
		opencode-nix \
		nix-homebrew \
		homebrew-core \
		homebrew-cask

# Update and switch
.PHONY: upgrade
upgrade: update switch

# Explicit Homebrew upgrade; switch does not upgrade brews/casks.
.PHONY: brew-upgrade
brew-upgrade:
ifeq ($(UNAME),Darwin)
	brew update
	brew upgrade
	brew upgrade --cask
else
	@echo "brew-upgrade is only available on macOS"
endif

# Garbage collection
.PHONY: clean
clean:
	nix-collect-garbage -d

# Aggressive cleanup (30 day old generations)
.PHONY: deep-clean
deep-clean:
	nix-collect-garbage --delete-older-than 30d
	@echo "Optimizing nix store..."
	nix store optimise

# Format all supported repository files
.PHONY: fmt
fmt:
	$(CHECK_SHELL) treefmt --config-file home/treefmt.toml --tree-root .
	$(CHECK_SHELL) treefmt --config-file home/treefmt.toml --tree-root ../modules

# Host-specific overrides (use when not running on the target host)
.PHONY: tpad
tpad:
	home-manager switch -b backup --flake .#mikaelsiidorow@tpad

# Show system generations
.PHONY: history
history:
ifneq ($(HOST_KIND),home)
	sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
else
	home-manager generations
endif

# Rollback to previous generation
.PHONY: rollback
rollback:
ifeq ($(UNAME),Darwin)
	$(BUILD_CMD) rollback
else ifeq ($(HOST_KIND),nixos)
	$(BUILD_CMD) switch --rollback
else
	home-manager switch --rollback
endif

# Verify flake inputs are up to date
.PHONY: check-updates
check-updates:
	nix flake metadata
	@echo ""
	@echo "Run 'make update' to update all inputs"

# Show flake info
.PHONY: info
info:
	nix flake show

# Test build without switching (useful for CI/testing)
.PHONY: test
test: check build

# Preview the NixOS Plasma desktop without activating it on the host.
.PHONY: plasma-vm
plasma-vm:
	nix build .\#nixosConfigurations.nixos-laptop-vm.config.system.build.vm -o result-plasma-vm
	./result-plasma-vm/bin/run-nixos-laptop-vm
