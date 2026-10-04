# Home-manager for the main user, with the shell environment shared with the
# workstations (modules/home/core).
{
  inputs,
  pkgs,
  username,
  ...
}:
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  programs.zsh.enable = true;
  users.users.${username}.shell = pkgs.zsh;
  # Lets zsh complete commands from system packages too.
  environment.pathsToLink = [ "/share/zsh" ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    # Move pre-existing files aside (e.g. ~/.config/gh/config.yml) instead of
    # failing activation.
    backupFileExtension = "backup";
    extraSpecialArgs = {
      inherit inputs;
      isDarwin = false;
    };
    users.${username} = {
      imports = [ ../../../../modules/home/core ];
      home.stateVersion = "26.05";

      # Persistent sessions for SSH: `tmux new -A -s main` reattaches.
      programs.tmux = {
        enable = true;
        clock24 = true;
        historyLimit = 50000;
        mouse = true;
        terminal = "tmux-256color";
      };
    };
  };
}
