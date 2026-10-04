# Linux-specific desktop applications
{
  pkgs,
  pkgs-unstable,
  lib,
  isNixOS ? false,
  ...
}:
let
  # Keep Pop!_OS Steam and all of its helper scripts on the host toolchain.
  # Mixing Nix coreutils with Steam's older glibc causes commands such as
  # dirname to fail once Steam configures its runtime library path.
  steam-system = pkgs.writeShellScriptBin "steam" ''
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games"
    unset LD_LIBRARY_PATH
    exec /usr/games/steam "$@"
  '';

  steam-desktop = pkgs.makeDesktopItem {
    name = "steam";
    desktopName = "Steam";
    comment = "Application for managing and playing games on Steam";
    exec = "${steam-system}/bin/steam %U";
    icon = "steam";
    terminal = false;
    categories = [ "Game" ];
    mimeTypes = [
      "x-scheme-handler/steam"
      "x-scheme-handler/steamlink"
    ];
  };

  # Launches the Steam-installed Godot so playtime is tracked.
  # Steam appid 404790 = Godot Engine.
  godot-steam = pkgs.writeShellScriptBin "godot-steam" ''
    exec ${steam-system}/bin/steam -applaunch 404790 "$@"
  '';
in
{
  home.packages =
    (with pkgs; [
      # Communication
      pkgs-unstable.thunderbird
      pkgs-unstable.vesktop
      # telegram-desktop - using flatpak instead due to graphics driver issues

      # bitwarden-desktop is temporarily omitted: nixos-26.05 packages it with
      # Electron 39, which nixpkgs marks as EOL/insecure.

      # Game development
      pkgs-unstable.godot_4

      # Productivity
      obsidian
      sweethome3d.application

      # Cloud
      stripe-cli

      # Document processing
      texliveFull
      inkscape

      # Screenshot
      flameshot

      # Terminal
      ghostty
    ])
    ++ lib.optionals (!isNixOS) [
      steam-system
      godot-steam
    ];

  # Steam creates its own user-level desktop symlink, which takes precedence
  # over entries in the Home Manager profile. Replace it declaratively so
  # desktop launches use the same system-runtime wrapper as terminal launches.
  xdg.dataFile."applications/steam.desktop" = lib.mkIf (!isNixOS) {
    source = "${steam-desktop}/share/applications/steam.desktop";
    force = true;
  };
}
