# Agent config: cross-machine authored files.
#
# Keep mutable runtime files (auth, caches, local settings, histories) out of
# Nix. This module only links files we intentionally author in this repo,
# plus a Claude settings baseline.
{
  lib,
  pkgs,
  ...
}:
let
  # Merged into ~/.claude/settings.json on switch: these keys win, lists are
  # unioned, removals need a manual edit. Public repo: keep work settings local.
  claudeSettings = pkgs.writeText "claude-settings-baseline.json" (
    builtins.toJSON {
      attribution = {
        commit = "";
        pr = "";
      };
      statusLine = {
        type = "command";
        command = "~/.claude/statusline-command.sh";
      };
      theme = "dark";
      verbose = true;
      autoMemoryEnabled = false;
      promptSuggestionEnabled = false;
      # The sandbox blocks the fsmonitor socket; skip it to avoid IPC errors.
      env = {
        GIT_CONFIG_COUNT = "1";
        GIT_CONFIG_KEY_0 = "core.fsmonitor";
        GIT_CONFIG_VALUE_0 = "false";
      };
      sandbox = {
        # Go CLIs (gh, terraform, kubectl) need trustd to verify TLS on macOS.
        enableWeakerNetworkIsolation = true;
        excludedCommands = [
          "git push *"
          "git pull *"
          "git fetch *"
          "git lfs *"
          "git -C * fetch *"
          "git -C * pull *"
        ];
      };
    }
  );

  # Like jq's `*`, but unions arrays instead of replacing them.
  claudeSettingsMerge = pkgs.writeText "claude-settings-merge.jq" ''
    def merge($a; $b):
      if ($a | type) == "object" and ($b | type) == "object" then
        reduce ($b | keys_unsorted[]) as $k ($a; .[$k] = merge($a[$k]; $b[$k]))
      elif ($a | type) == "array" and ($b | type) == "array" then
        $a + ($b - $a)
      else
        $b
      end;
    merge(.[0]; .[1])
  '';

  skillTargets = {
    codex = name: ".codex/skills/${name}";
    claude-code = name: ".claude/skills/${name}";
    opencode = name: ".config/opencode/skills/${name}";
  };

  skillTargetPaths =
    name: agents:
    let
      # OpenCode also reads ~/.claude/skills. If a skill targets both tools,
      # install it once there so OpenCode does not see duplicate skill names.
      effectiveAgents =
        if builtins.elem "claude-code" agents && builtins.elem "opencode" agents then
          builtins.filter (agent: agent != "opencode") agents
        else
          agents;
    in
    lib.unique (map (agent: skillTargets.${agent} name) effectiveAgents);

  skills = {
    babysit = {
      source = ./skills/babysit;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    humanizer = {
      source = ./skills/humanizer;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    ponytail = {
      source = ./skills/ponytail;
      agents = [
        "codex"
        "claude-code"
        "opencode"
      ];
    };

    # cursor-agent reads ~/.claude/skills, so the claude-code target covers it.
    # Disabled while Cursor CLI is unused (see packages.nix).
    # cursor-agent = {
    #   source = ./skills/cursor-agent;
    #   agents = [ "claude-code" ];
    # };
  };

  mkSkillFiles =
    name: skill:
    lib.listToAttrs (
      map (path: {
        name = path;
        value = {
          inherit (skill) source;
        };
      }) (skillTargetPaths name skill.agents)
    );

  skillFiles = lib.foldl' (acc: fileSet: acc // fileSet) { } (lib.mapAttrsToList mkSkillFiles skills);
in
{
  home.file = skillFiles // {
    ".claude/CLAUDE.md".source = ./shared/AGENTS.md;
    ".codex/AGENTS.md".source = ./shared/AGENTS.md;
    ".codex/rules/nix-managed.rules".source = ./codex/rules/nix-managed.rules;
    ".claude/statusline-command.sh" = {
      source = ./claude-code/statusline-command.sh;
      # Claude Code runs the statusLine command through a shell, so the file
      # must be executable; nix store copies are read-only without this.
      executable = true;
    };
    # Disabled while Cursor CLI is unused (see packages.nix).
    # ".cursor/statusline.sh" = {
    #   source = ./cursor/statusline.sh;
    #   # Cursor CLI spawns this without a shell, so it must be executable.
    #   executable = true;
    # };
  };

  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claude_settings="$HOME/.claude/settings.json"
    if [ -L "$claude_settings" ]; then
      warnEcho "Skipping Claude settings merge: $claude_settings is a symlink"
    elif [ -e "$claude_settings" ] && ! ${lib.getExe pkgs.jq} -e . "$claude_settings" >/dev/null 2>&1; then
      warnEcho "Skipping Claude settings merge: $claude_settings is not valid JSON"
    else
      claude_merged="$(mktemp)"
      if [ -e "$claude_settings" ]; then
        ${lib.getExe pkgs.jq} -s -f ${claudeSettingsMerge} "$claude_settings" ${claudeSettings} >"$claude_merged"
      else
        ${lib.getExe pkgs.jq} . ${claudeSettings} >"$claude_merged"
      fi
      if ! cmp -s "$claude_merged" "$claude_settings"; then
        run mkdir -p "$HOME/.claude"
        run install -m 600 "$claude_merged" "$claude_settings"
      fi
      rm -f "$claude_merged"
    fi
  '';
}
