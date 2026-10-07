# User-level Nix client configuration.
{
  config,
  lib,
  isDarwin ? false,
  ...
}:
{
  sops.templates."nix-access-tokens.conf".content = ''
    access-tokens = github.com=${config.sops.placeholder."github/token"}
  '';

  xdg.configFile."nix/nix.conf".text = ''
    experimental-features = nix-command flakes
  ''
  # llm-agents packages are only cached here; darwin sets it system-wide.
  # The daemon must list it in extra-trusted-substituters with its key (see README).
  + lib.optionalString (!isDarwin) ''
    extra-substituters = https://cache.numtide.com
  ''
  + ''
    !include ${config.sops.templates."nix-access-tokens.conf".path}
  '';
}
