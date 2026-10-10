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
  claude = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  codex = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  codexProfile = lib.optionalString (hostname == "tpad") " --profile hestia";
  # Keep both the settings overlay and shell exports: --settings overrides
  # user/project env settings, while exports pass the routing to child processes.
  claudeHestiaSettings = pkgs.writeText "claude-hestia-settings.json" (
    builtins.toJSON {
      env = {
        ANTHROPIC_BASE_URL = "https://hestia.vpn.miksu.app:8317";
        # Hestia restricts access to the tailnet and has no client API keys.
        # Override local credentials so the proxy owns upstream authentication.
        ANTHROPIC_AUTH_TOKEN = "hestia-tailnet";
        # unset below only clears the shell; settings could restore a saved key.
        ANTHROPIC_API_KEY = "";
        CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
      };
    }
  );
  claudeHestia = pkgs.writeShellApplication {
    name = "claude-hestia";
    text = ''
      export ANTHROPIC_BASE_URL=https://hestia.vpn.miksu.app:8317
      export ANTHROPIC_AUTH_TOKEN=hestia-tailnet
      unset ANTHROPIC_API_KEY
      export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
      exec ${claude}/bin/claude --settings ${claudeHestiaSettings} "$@"
    '';
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
  ]
  # Cursor CLI (not in claude-code-nix-style flake; from unstable)
  ++ lib.optionals isDarwin [ pkgs-unstable.cursor-cli ];

  programs.zsh.shellAliases = {
    c = "claude";
    claude-yolo = "claude --dangerously-skip-permissions";
    cco = "claude --continue";
    cres = "claude --resume";
    crew = "claude /review";
    codex = "${codex}/bin/codex --ask-for-approval on-request -c 'approvals_reviewer=\"auto_review\"' -c 'default_permissions=\":workspace\"' -c 'plan_mode_reasoning_effort=\"xhigh\"' -c 'web_search=\"live\"'${codexProfile}";
    codex-yolo = "${codex}/bin/codex --ask-for-approval never -c 'default_permissions=\":danger-full-access\"' -c 'plan_mode_reasoning_effort=\"xhigh\"' -c 'web_search=\"live\"'${codexProfile}";
  };
}
