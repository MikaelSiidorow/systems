# Shared launcher configuration for Raycast on macOS and Vicinae on Linux.
{
  config,
  hostname ? null,
  isDarwin ? false,
  lib,
  pkgs,
  ...
}:
let
  isLinux = !isDarwin;
  isGenericLinux = config.targets.genericLinux.enable or false;

  launcherKeybindingPath = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/launcher/";

  buildNodeExtension =
    {
      name,
      src,
      installPhase,
      npmDepsHash ? null,
    }:
    pkgs.buildNpmPackage (
      {
        inherit name src installPhase;
      }
      // (
        if npmDepsHash != null then
          { inherit npmDepsHash; }
        else
          {
            inherit (pkgs.importNpmLock) npmConfigHook;
            npmDeps = pkgs.importNpmLock { npmRoot = src; };
          }
      )
    );

  mkRaycastExtension =
    {
      name,
      src ? null,
      rev ? null,
      sha256 ? null,
      npmDepsHash ? null,
    }:
    let
      resolvedSrc =
        if src != null then
          src
        else
          pkgs.fetchgit {
            inherit rev sha256;
            url = "https://github.com/raycast/extensions";
            sparseCheckout = [ "/extensions/${name}" ];
          }
          + "/extensions/${name}";
    in
    buildNodeExtension {
      inherit name npmDepsHash;
      src = resolvedSrc;
      installPhase = ''
        runHook preInstall

        mkdir -p $out
        cp -r /build/.config/raycast/extensions/${name}/* $out/

        runHook postInstall
      '';
    };

  mkVicinaeExtension =
    {
      name,
      src,
      npmDepsHash ? null,
    }:
    buildNodeExtension {
      inherit name src npmDepsHash;
      installPhase = ''
        runHook preInstall

        mkdir -p $out
        cp -r /build/.local/share/vicinae/extensions/${name}/* $out/

        runHook postInstall
      '';
    };

  machines = {
    tpad = {
      linux.vicinae.enableGnomeExtension = false;
      darwin.raycast.linkLocalExtensions = false;
    };

  };

  machine = lib.recursiveUpdate {
    linux.vicinae.enableGnomeExtension = false;
    darwin.raycast = {
      defaults = { };
      linkLocalExtensions = false;
    };
  } (machines.${hostname} or { });

  shared = {
    hotkeys = {
      linux = "<Super>space";
      raycast = "Option Space";
    };

    extensions = {
      # Add Raycast Store extensions here once pinned. Vicinae can consume
      # these directly; Raycast linking is kept opt-in below because Raycast's
      # installed-extension registry is private app state.
      #
      # raycast = [
      #   {
      #     name = "google-translate";
      #     rev = "raycast/extensions commit";
      #     sha256 = lib.fakeHash;
      #     npmDepsHash = lib.fakeHash;
      #   }
      # ];
      raycast = [ ];

      # Add native Vicinae extensions here if needed.
      vicinae = [ ];
    };

    settings = {
      # Keep Vicinae mostly on its own defaults while matching launcher
      # behavior expected from Raycast.
      close_on_focus_loss = true;
      favorites = [
        "clipboard:history"
        "applications:firefox"
        "applications:com.mitchellh.ghostty"
        "applications:dev.zed.Zed"
      ];
    };
  };

  linux = {
    vicinae = {
      package = pkgs.vicinae;
      extensions =
        (map mkRaycastExtension shared.extensions.raycast)
        ++ (map mkVicinaeExtension shared.extensions.vicinae);
      inherit (shared) settings;
    };
  };

  darwin = {
    raycast = {
      defaults = machine.darwin.raycast.defaults or { };
      manifest = {
        managed_by = "home/launcher.nix";
        inherit hostname shared;
        note = "Raycast does not expose a stable declarative settings module; add known-safe defaults under machines.<host>.darwin.raycast.defaults.";
      };
    };
  };

  raycastExtensionFiles = builtins.listToAttrs (
    map (extension: {
      name = ".config/raycast/extensions/${extension.name}";
      value.source = mkRaycastExtension extension;
    }) shared.extensions.raycast
  );
in
{
  programs.vicinae = lib.mkIf isLinux {
    enable = true;
    package = linux.vicinae.package;
    systemd = {
      enable = true;
      autoStart = true;
    };
    extensions = linux.vicinae.extensions;
    settings = linux.vicinae.settings;
  };

  dconf.settings = lib.mkIf isGenericLinux {
    "org/gnome/desktop/wm/keybindings" = {
      switch-input-source = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
      switch-input-source-backward = [ "<Shift><Super>space" ];
    };

    "desktop/ibus/general/hotkey" = {
      triggers = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = lib.mkAfter [ launcherKeybindingPath ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/launcher" = {
      name = "Vicinae";
      command = "${linux.vicinae.package}/bin/vicinae toggle";
      binding = shared.hotkeys.linux;
    };

    "org/gnome/shell" = lib.mkIf machine.linux.vicinae.enableGnomeExtension {
      enabled-extensions = lib.mkAfter [ "vicinae@dagimg-dot" ];
    };
  };

  home.packages = lib.optionals (isLinux && machine.linux.vicinae.enableGnomeExtension) [
    pkgs.gnomeExtensions.vicinae
  ];

  home.file =
    lib.optionalAttrs isDarwin {
      "Library/Application Support/Raycast/nix/launcher.json".text =
        builtins.toJSON darwin.raycast.manifest;
    }
    // lib.optionalAttrs (isDarwin && machine.darwin.raycast.linkLocalExtensions) raycastExtensionFiles;

  targets.darwin.defaults = lib.mkIf (isDarwin && darwin.raycast.defaults != { }) {
    "com.raycast.macos" = darwin.raycast.defaults;
  };
}
