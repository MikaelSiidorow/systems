{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  dashboardVersion = builtins.substring 0 12 (
    builtins.hashString "sha256" (
      builtins.hashFile "sha256" ./mythos-dashboard.js + builtins.hashFile "sha256" ./mythos-dashboard.css
    )
  );
  mythosDashboard = pkgs.stdenvNoCC.mkDerivation {
    pname = "mythos-dashboard";
    version = dashboardVersion;
    dontUnpack = true;
    installPhase = ''
      install -Dm0444 ${./mythos-dashboard.js} "$out/mythos-dashboard.js"
      install -Dm0444 ${./mythos-dashboard.css} "$out/mythos-dashboard.css"
    '';
    passthru.entrypoint = "mythos-dashboard.js";
  };
in
{
  # Keep the Home Assistant configuration and entities in Nix, but implement
  # the information display as an ordinary typed web component. Home Assistant
  # injects live entity state through the component's `hass` property.
  services.home-assistant = {
    customLovelaceModules = lib.mkForce [
      mythosDashboard
      unstablePkgs.home-assistant-custom-lovelace-modules.kiosk-mode
    ];

    lovelaceConfig = lib.mkForce {
      title = "Information display";
      kiosk_mode.kiosk = true;
      views = [
        {
          title = "Home";
          path = "home";
          panel = true;
          cards = [ { type = "custom:mythos-dashboard"; } ];
        }
        {
          title = "Cast";
          path = "cast";
          visible = false;
          cards = [
            {
              type = "custom:mythos-dashboard";
              cast_view = true;
            }
          ];
        }
      ];
    };

    config = {
      script.show_information_display_on_tv = {
        alias = "Show information display on TV";
        icon = "mdi:cast-connected";
        mode = "restart";
        sequence = [
          {
            action = "cast.show_lovelace_view";
            data = {
              entity_id = "media_player.living_room_tv";
              dashboard_path = "information-display";
              view_path = "cast";
            };
          }
        ];
      };

      input_boolean.information_display_morning_active = {
        name = "Morning information display active";
        icon = "mdi:television-dashboard";
      };

      input_boolean.guest_wifi_qr = {
        name = "Show guest Wi-Fi QR";
        icon = "mdi:qrcode";
        initial = false;
      };

      "automation information_display" = [
        {
          id = "information_display_weekday_start";
          alias = "Information display · weekday start";
          mode = "single";
          triggers = [
            {
              trigger = "time";
              at = "07:00:00";
            }
          ];
          conditions = [
            {
              condition = "time";
              weekday = [
                "mon"
                "tue"
                "wed"
                "thu"
                "fri"
              ];
            }
          ];
          actions = [
            {
              action = "media_player.turn_on";
              target.entity_id = "media_player.living_room_tv";
              continue_on_error = true;
            }
            { delay.seconds = 5; }
            { action = "script.show_information_display_on_tv"; }
            {
              action = "input_boolean.turn_on";
              target.entity_id = "input_boolean.information_display_morning_active";
            }
          ];
        }
        {
          id = "information_display_weekday_stop";
          alias = "Information display · weekday stop";
          mode = "single";
          triggers = [
            {
              trigger = "time";
              at = "09:00:00";
            }
          ];
          conditions = [
            {
              condition = "time";
              weekday = [
                "mon"
                "tue"
                "wed"
                "thu"
                "fri"
              ];
            }
            {
              condition = "state";
              entity_id = "input_boolean.information_display_morning_active";
              state = "on";
            }
          ];
          actions = [
            {
              action = "media_player.turn_off";
              target.entity_id = "media_player.living_room_tv";
              continue_on_error = true;
            }
            {
              action = "input_boolean.turn_off";
              target.entity_id = "input_boolean.information_display_morning_active";
            }
          ];
        }
        {
          id = "information_display_guest_wifi_timeout";
          alias = "Information display · hide guest Wi-Fi QR";
          mode = "restart";
          triggers = [
            {
              trigger = "state";
              entity_id = "input_boolean.guest_wifi_qr";
              to = "on";
            }
          ];
          actions = [
            { delay.minutes = 30; }
            {
              action = "input_boolean.turn_off";
              target.entity_id = "input_boolean.guest_wifi_qr";
            }
          ];
        }
      ];
    };
  };
}
