# GNOME desktop settings for Linux
{ lib, ... }:
{
  dconf.settings = {
    # Interface: clock, theme, fonts
    "org/gnome/desktop/interface" = {
      clock-format = "24h";
      color-scheme = "prefer-dark";
      show-battery-percentage = true;
      font-name = "Inter 11";
      monospace-font-name = "Roboto Mono 11";
    };

    # Keyboard layouts: Finnish + Pinyin
    "org/gnome/desktop/input-sources" = {
      sources = [
        (lib.gvariant.mkTuple [
          "xkb"
          "fi+classic"
        ])
        (lib.gvariant.mkTuple [
          "ibus"
          "libpinyin"
        ])
      ];
      per-window = false;
    };

    # Mouse
    "org/gnome/desktop/peripherals/mouse" = {
      natural-scroll = false;
    };

    # Touchpad
    "org/gnome/desktop/peripherals/touchpad" = {
      natural-scroll = true;
      two-finger-scrolling-enabled = true;
      disable-while-typing = false;
    };

    # Privacy
    "org/gnome/desktop/privacy" = {
      recent-files-max-age = 30;
      remove-old-temp-files = true;
      remove-old-trash-files = true;
    };

    # Session: 8min idle
    "org/gnome/desktop/session" = {
      idle-delay = lib.gvariant.mkUint32 480;
    };

    # Power: 30min sleep on AC and battery
    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-timeout = 1800;
      sleep-inactive-battery-timeout = 1800;
    };

    # Nautilus: list view by default
    "org/gnome/nautilus/preferences" = {
      default-folder-viewer = "list-view";
    };

    # Dock: pinned apps and autohide (similar to macOS config)
    "org/gnome/shell" = {
      enabled-extensions = [
        # Pop!_OS system extensions
        "cosmic-dock@system76.com"
        "pop-cosmic@system76.com"
        "pop-shell@system76.com"
        "popx11gestures@system76.com"
        "system76-power@system76.com"
        "ubuntu-appindicators@ubuntu.com"
        # Nix-managed extensions
        "Vitals@CoreCoding.com"
      ];
      disabled-extensions = [
        "cosmic-workspaces@system76.com"
        "ding@rastersoft.com"
      ];
      favorite-apps = [
        "org.gnome.Nautilus.desktop"
        "io.elementary.appcenter.desktop"
        "com.google.Chrome.desktop"
        "firefox.desktop"
        "com.mitchellh.ghostty.desktop"
        "code.desktop"
        "dev.zed.Zed.desktop"
        "t3code.desktop"
        "vesktop.desktop"
        "org.telegram.desktop.desktop"
      ];
    };

    # Pop Cosmic: hide top-left buttons (replaced by Vitals)
    "org/gnome/shell/extensions/pop-cosmic" = {
      show-applications-button = false;
      show-workspaces-button = false;
    };

    # Vitals: system monitor in top bar
    # NOTE: GNOME 42 has a GJS bug where any extension polling on a timer can
    # trigger GC crashes (fixed in GJS 1.76 / GNOME 44+). Longer update-time
    # reduces the chance of hitting it. See pop-os/pop#2893.
    "org/gnome/shell/extensions/vitals" = {
      update-time = 15;
      hot-sensors = [
        "_memory_usage_"
        "_processor_usage_"
      ];
      position-in-panel = 0; # left
      show-temperature = false;
      show-voltage = false;
      show-fan = false;
      show-memory = true;
      show-processor = true;
      show-network = false;
      show-storage = false;
      show-battery = false;
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      dock-fixed = false;
      autohide = true;
      intellihide = false;
      extend-height = false;
      show-trash = false;
      show-mounts = false;
      dash-max-icon-size = 48;
      show-show-apps-button = true;
    };

    # Disable GNOME's built-in screenshot UI
    "org/gnome/shell/keybindings" = {
      show-screenshot-ui = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
    };

    # Custom keybindings and disable default terminal
    "org/gnome/settings-daemon/plugins/media-keys" = {
      terminal = lib.gvariant.mkEmptyArray lib.gvariant.type.string;
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
      ];
    };

    # Ghostty keybinding: Super+T
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Ghostty";
      command = "ghostty";
      binding = "<Super>t";
    };

    # Flameshot screenshot: Print Screen
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1" = {
      name = "Flameshot";
      command = "flameshot gui";
      binding = "Print";
    };
  };
}
