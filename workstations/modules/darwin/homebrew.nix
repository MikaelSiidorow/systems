# Homebrew configuration for macOS
{ config, ... }:
{
  homebrew = {
    enable = true;

    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall";
      # cleanup = "zap";
      upgrade = true;
    };

    # Disabled: ~/.Brewfile below already points at the generated Brewfile, and the
    # HOMEBREW_BUNDLE_FILE this sets makes `brew bundle --global` error out.
    # global = {
    #   brewfile = true;
    # };

    taps = builtins.attrNames config.nix-homebrew.taps;

    greedyCasks = true;

    # Chrome, 1Password, Teams and drata-agent come from the enterprise MDM.
    casks = [
      # "ghostty" # Now installed and updated by the enterprise MDM.
      "cmux"
      "postico"
      # "raycast" # Now installed and updated by the enterprise MDM.
    ];
  };

  home-manager.users.${config.system.primaryUser}.home.file.".Brewfile".text =
    config.homebrew.brewfile;
}
