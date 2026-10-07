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
  # Requires this user in trusted-users (see README).
  + lib.optionalString (!isDarwin) ''
    extra-substituters = https://cache.numtide.com
    extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
  ''
  + ''
    !include ${config.sops.templates."nix-access-tokens.conf".path}
  '';
}
