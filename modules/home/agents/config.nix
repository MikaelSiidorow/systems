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
          # Codex needs to write ~/.codex and applies its own sandbox.
          "codex *"
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

  # Merged into ~/.codex/config.toml on switch: these keys win, the rest of
  # the file keeps its layout. Codex defaults to auto mode.
  codexSettings = (pkgs.formats.toml { }).generate "codex-config-baseline.toml" {
    approval_policy = "on-request";
    default_permissions = ":workspace";
    approvals_reviewer = "auto_review";
    model_reasoning_effort = "medium";
    plan_mode_reasoning_effort = "xhigh";
    web_search = "live";
  };

  codexPython = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);

  codexSettingsMerge = pkgs.writeText "codex-config-merge.py" ''
    import sys

    import tomlkit


    def merge(dst, src):
        for key, value in src.items():
            if isinstance(value, dict) and isinstance(dst.get(key), dict):
                merge(dst[key], value)
            else:
                dst[key] = value


    config, baseline = sys.argv[1:]
    with open(config) as f:
        doc = tomlkit.parse(f.read())
    with open(baseline) as f:
        merge(doc, tomlkit.parse(f.read()))
    sys.stdout.write(tomlkit.dumps(doc))
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
    address-review = {
      source = ./skills/address-review;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    babysit-pr = {
      source = ./skills/babysit-pr;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    dependency-prs = {
      source = ./skills/dependency-prs;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    file-pr = {
      source = ./skills/file-pr;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    full-send = {
      source = ./skills/full-send;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    full-stop = {
      source = ./skills/full-stop;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    grilling = {
      source = ./skills/grilling;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    morning-prs = {
      source = ./skills/morning-prs;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    rebase = {
      source = ./skills/rebase;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    review-pr = {
      source = ./skills/review-pr;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    review-rounds = {
      source = ./skills/review-rounds;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    unslop = {
      source = ./skills/unslop;
      agents = [
        "codex"
        "claude-code"
      ];
    };

    writing-for-agents = {
      source = ./skills/writing-for-agents;
      agents = [
        "codex"
        "claude-code"
      ];
    };
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
  home = {
    file = skillFiles // {
      ".claude/CLAUDE.md".source = ./shared/AGENTS.md;
      ".codex/AGENTS.md".source = ./shared/AGENTS.md;
      ".codex/rules/nix-managed.rules".source = ./codex/rules/nix-managed.rules;
      ".claude/statusline-command.sh" = {
        source = ./claude-code/statusline-command.sh;
        # Claude Code runs the statusLine command through a shell, so the file
        # must be executable; nix store copies are read-only without this.
        executable = true;
      };
    };

    activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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

    activation.codexSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      codex_config="$HOME/.codex/config.toml"
      codex_merged="$(mktemp)"
      if [ -L "$codex_config" ]; then
        warnEcho "Skipping Codex config merge: $codex_config is a symlink"
      elif [ ! -e "$codex_config" ]; then
        run mkdir -p "$HOME/.codex"
        run install -m 600 ${codexSettings} "$codex_config"
      elif ! ${codexPython.interpreter} ${codexSettingsMerge} "$codex_config" ${codexSettings} >"$codex_merged"; then
        warnEcho "Skipping Codex config merge: $codex_config is not valid TOML"
      elif ! cmp -s "$codex_merged" "$codex_config"; then
        run install -m 600 "$codex_merged" "$codex_config"
      fi
      rm -f "$codex_merged"
    '';
  };
}
