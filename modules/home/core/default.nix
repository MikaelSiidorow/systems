# Shell environment shared by every machine with home-manager: the
# workstations and, later, Hestia.
{ inputs, ... }:
{
  imports = [
    ./direnv.nix
    ./nix-index.nix
    ./packages.nix
    ./zsh.nix
    inputs.nix-index-database.homeModules.nix-index
  ];
}
