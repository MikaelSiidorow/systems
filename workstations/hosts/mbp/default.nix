# MacBook Pro (work) nix-darwin host configuration
{ username, ... }:
{
  imports = [ ../../modules/darwin ];

  system.primaryUser = username;
  users.users.${username}.home = "/Users/${username}";
  home-manager.users.${username}.imports = [
    ./telemetry.nix
    ./away.nix
  ];
}
