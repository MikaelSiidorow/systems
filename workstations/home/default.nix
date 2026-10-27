# Home-manager configuration entry point
{
  lib,
  inputs,
  isDarwin ? false,
  ...
}:
{
  imports = [
    ../../modules/home/core
    ../../modules/home/agents
    ./packages.nix
    ./nix.nix
    ./git.nix
    ./github-auth.nix
    ./applications.nix
    ./launcher.nix
    ./zed.nix
    ./package-managers
    inputs.sops-nix.homeManagerModules.sops
    ./sops.nix
  ]
  ++ lib.optionals isDarwin [
    ./colima.nix
  ]
  ++ lib.optionals (!isDarwin) [
    ./applications-linux.nix
    ./gnome.nix
    # Firefox is not approved on the work (darwin) machine.
    ./firefox.nix
  ];

  home = {
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;
}
