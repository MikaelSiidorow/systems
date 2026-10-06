# macOS system defaults
{
  pkgs,
  inputs,
  username,
  ...
}:
let
  t3code = import ../../../modules/t3code.nix {
    inherit pkgs inputs;
    codex = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
in
{
  environment.systemPackages = [ t3code.desktop ] ++ t3code.direnvProviders;

  system.defaults = {
    NSGlobalDomain.AppleICUForce24HourTime = true;
    menuExtraClock.ShowSeconds = true;
    dock = {
      launchanim = false;
      tilesize = 48;
      autohide = true;
      show-recents = false;
      orientation = "bottom";
      persistent-apps = [
        {
          app = "/System/Library/CoreServices/Finder.app";
        }
        {
          app = "/System/Applications/Notes.app";
        }
        {
          app = "/System/Applications/System Settings.app";
        }
        {
          app = "/Applications/Microsoft Teams.app";
        }
        {
          app = "/Applications/1Password.app";
        }
        {
          app = "/Applications/Google Chrome.app";
        }
        {
          app = "/Applications/Ghostty.app";
        }
        {
          app = "/Applications/cmux.app";
        }
        {
          app = "${t3code.desktop}/Applications/${t3code.unwrapped.appName}.app";
        }
        {
          app = "${pkgs.zed-editor}/Applications/Zed.app";
        }
      ];
    };
    # Use CustomUserPreferences for persistent-others so we can set view
    # options. The typed `dock.persistent-others` only accepts paths.
    # arrangement: 1=name 2=date-added 3=date-modified 4=date-created 5=kind
    # displayas:   0=stack 1=folder
    # showas:      0=auto 1=fan 2=grid 3=list
    CustomUserPreferences = {
      # Keep natural scrolling on the trackpad, but reverse vertical scrolling
      # for external mouse wheels.
      "com.pilotmoon.scroll-reverser" = {
        InvertScrollingOn = true;
        ReverseX = false;
        ReverseY = true;
        ReverseTrackpad = false;
        ReverseMouse = true;
      };
      "com.apple.dock".persistent-others = [
        {
          tile-type = "directory-tile";
          tile-data = {
            file-label = "Downloads";
            file-type = 2;
            arrangement = 2;
            displayas = 0;
            showas = 1;
            file-data = {
              _CFURLString = "file:///Users/${username}/Downloads/";
              _CFURLStringType = 15;
            };
          };
        }
      ];
      # Keyboard input sources: only Finnish (drop the default Swedish layout),
      # keeping the character/emoji viewer.
      "com.apple.HIToolbox" = {
        AppleEnabledInputSources = [
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = 17;
            "KeyboardLayout Name" = "Finnish";
          }
          {
            "Bundle ID" = "com.apple.CharacterPaletteIM";
            InputSourceKind = "Non Keyboard Input Method";
          }
        ];
        AppleSelectedInputSources = [
          {
            InputSourceKind = "Keyboard Layout";
            "KeyboardLayout ID" = 17;
            "KeyboardLayout Name" = "Finnish";
          }
        ];
      };
      # Rebind "Move focus to next window" (default ⌘`) to ⌘§ so the section key
      # left of 1 cycles windows of the active app (⌘⇧§ cycles backwards). This is
      # symbolic hotkey 27; parameters = (character, key code, modifier mask):
      #   167     = "§" character
      #   10      = key code of the § / ISO section key (left of 1)
      #   1048576 = ⌘ (Command) modifier
      "com.apple.symbolichotkeys".AppleSymbolicHotKeys."27" = {
        enabled = 1;
        value = {
          type = "standard";
          parameters = [
            167
            10
            1048576
          ];
        };
      };
    };
  };
}
