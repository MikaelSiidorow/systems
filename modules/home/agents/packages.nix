# Coding agent CLIs and their shell aliases.
{
  pkgs,
  lib,
  inputs,
  pkgs-unstable,
  hostname ? "",
  isDarwin ? false,
  ...
}:
let
  codex = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  codexProfile = lib.optionalString (hostname == "tpad") " --profile hestia";
in
{
  home.packages = [
    inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
    codex
  ]
  # NixOS/Linux only - macOS uses Homebrew
  ++ lib.optionals (!isDarwin) [
    inputs.opencode-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ]
  # Cursor CLI (not in claude-code-nix-style flake; from unstable)
  ++ lib.optionals isDarwin [ pkgs-unstable.cursor-cli ];

  programs.zsh.shellAliases = {
    c = "claude";
    claude-yolo = "claude --dangerously-skip-permissions";
    cco = "claude --continue";
    cres = "claude --resume";
    crew = "claude /review";
    cwt = "claude-worktree";
    codex = "${codex}/bin/codex --ask-for-approval on-request -c 'approvals_reviewer=\"auto_review\"' -c 'default_permissions=\":workspace\"' -c 'plan_mode_reasoning_effort=\"xhigh\"' -c 'web_search=\"live\"'${codexProfile}";
    codex-yolo = "${codex}/bin/codex --ask-for-approval never -c 'default_permissions=\":danger-full-access\"' -c 'plan_mode_reasoning_effort=\"xhigh\"' -c 'web_search=\"live\"'${codexProfile}";
  };
}
