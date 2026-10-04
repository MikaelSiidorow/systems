# Minimal KDE preferences; Plasma owns everything not listed here.
{ pkgs, inputs, ... }:
let
  t3code = import ../../modules/t3code.nix {
    inherit pkgs inputs;
    codex = inputs.codex-cli-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };
in
{
  home.packages = [ t3code.desktop ];

  programs.plasma = {
    enable = true;

    workspace.lookAndFeel = "org.kde.breezedark.desktop";

    input.keyboard.layouts = [ { layout = "fi"; } ];

    # Let KWin launch Fcitx through its native Wayland input-method protocol.
    configFile.kwinrc.Wayland.InputMethod = "/run/current-system/sw/share/applications/org.fcitx.Fcitx5.desktop";

    # ponytail: reuse Plasma's standard widgets and behavior.
    panels = [
      {
        location = "top";
        floating = true;
      }
    ];

    hotkeys.commands.vicinae = {
      name = "Vicinae";
      key = "Meta+Space";
      command = "vicinae toggle";
    };
  };
}
