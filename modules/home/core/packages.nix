# Everyday shell tools, shared by every machine with home-manager.
{
  pkgs,
  lib,
  ...
}:
{
  programs = {
    bat.enable = true;

    gh = {
      enable = true;
      extensions = [ pkgs.gh-stack ];
      settings.aliases.co = "pr checkout";
    };

    eza = {
      enable = true;
      enableZshIntegration = true;
      git = true;
      icons = "auto";
    };

    ripgrep.enable = true;

    fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    starship = {
      enable = true;
      enableZshIntegration = true;
      settings = {
        format = lib.concatStrings [
          "$directory"
          "$git_branch"
          "$git_status"
          "$nix_shell"
          "$cmd_duration"
          "$line_break"
          "$character"
        ];
        directory = {
          style = "bold blue";
          truncation_length = 3;
          truncate_to_repo = true;
        };
        git_branch.style = "bold purple";
        character = {
          success_symbol = "[>](bold green)";
          error_symbol = "[>](bold red)";
        };
        cmd_duration.min_time = 2000;
      };
    };
  };

  home.packages = with pkgs; [
    coreutils
    wget
    jq
    gettext
    fd
    btop
    tldr
    trash-cli
  ];
}
