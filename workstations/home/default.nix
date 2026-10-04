# Home-manager configuration entry point
{
  lib,
  inputs,
  isDarwin ? false,
  isNixOS ? false,
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
    ./skhd.nix
    ./colima.nix
  ]
  ++ lib.optionals (!isDarwin) [
    ./applications-linux.nix
    # Firefox is not approved on the work (darwin) machine.
    ./firefox.nix
  ]
  # GNOME config only on Pop!_OS (non-NixOS Linux)
  ++ lib.optionals (!isDarwin && !isNixOS) [
    ./gnome.nix
  ]
  ++ lib.optionals isNixOS [
    ./plasma.nix
  ];

  home = {
    stateVersion = "25.11";
  };

  programs.home-manager.enable = true;
}
