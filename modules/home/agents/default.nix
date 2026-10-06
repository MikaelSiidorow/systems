# Agent config: cross-machine authored files.
#
# Keep mutable runtime files (auth, caches, local settings, histories) out of
# Nix. This module only links files we intentionally author in this repo.
{
  lib,
  ...
}:
let
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
    cursor-agent = {
      source = ./skills/cursor-agent;
      agents = [ "claude-code" ];
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
  imports = [
    ./packages.nix
  ];

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
    ".cursor/statusline.sh" = {
      source = ./cursor/statusline.sh;
      # Cursor CLI spawns this without a shell, so it must be executable.
      executable = true;
    };
  };
}
