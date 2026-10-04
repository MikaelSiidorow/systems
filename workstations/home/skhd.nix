# skhd configuration - macOS only
_: {
  xdg.configFile."skhd/skhdrc" = {
    text = ''
      # -- App Switching Hotkeys --
      # Switches to an application, opening it if it's not already running.

      ctrl + cmd - 1 : open -a "Ghostty"
      ctrl + cmd - 2 : open -a "Zed"
      ctrl + cmd - 3 : open -a "Google Chrome"
      ctrl + cmd - 4 : open -a "Slack"

    '';
  };
}
