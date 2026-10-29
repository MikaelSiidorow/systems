# Coding agent CLIs and their shell aliases.
{
  pkgs,
  lib,
  inputs,
  hostname ? "",
  isDarwin ? false,
  ...
}:
let
  claude = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  codex = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  codexProfile = lib.optionalString (hostname == "tpad") " --profile hestia";
  claudeHestia = import ../../claude-proxy.nix {
    inherit pkgs claude;
  };
in
{
  home.packages = [
    claude
    codex
  ]
  ++ lib.optionals (hostname == "tpad") [ claudeHestia ]
  # NixOS/Linux only - macOS uses Homebrew
  ++ lib.optionals (!isDarwin) [
    inputs.opencode-nix.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
  # Cursor CLI (not in claude-code-nix-style flake; from unstable). Disabled
  # while unused; restore together with the cursor-agent skill and statusline
  # in config.nix, and re-add pkgs-unstable to the args above.
  # ++ lib.optionals isDarwin [ pkgs-unstable.cursor-cli ];

  programs.zsh.shellAliases = {
    c = "claude";
    claude-yolo = "claude --dangerously-skip-permissions";
    cco = "claude --continue";
    cres = "claude --resume";
    crew = "claude /review";
    # Shared defaults (auto mode, effort, web search) live in config.nix.
    codex = "${codex}/bin/codex${codexProfile}";
    codex-yolo = "${codex}/bin/codex --ask-for-approval never -c 'default_permissions=\":danger-full-access\"'${codexProfile}";
  };
}
