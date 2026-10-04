{
  config,
  inputs,
  pkgs,
  ...
}:
let
  unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  digitransitQuery = builtins.toJSON {
    query = ''
      {
        stop(id: "HSL:2215221") {
          stoptimesWithoutPatterns(numberOfDepartures: 12) {
            serviceDay
            scheduledDeparture
            realtimeDeparture
            departureDelay
            realtime
            realtimeState
            headsign
            trip {
              route {
                gtfsId
                shortName
              }
            }
          }
        }
      }
    '';
  };
in
{
  # Home Assistant moves faster than the NixOS stable release. Replace only
  # its stable module and package while keeping the rest of Hestia on stable.
  disabledModules = [ "services/home-automation/home-assistant.nix" ];
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/home-automation/home-assistant.nix"
    ./information-display.nix
  ];

  services.home-assistant = {
    enable = true;
    package = unstablePkgs.home-assistant.overrideAttrs (_: {
      doInstallCheck = false;
    });

    # Integrations added through the UI still need their Python dependencies
    # declared here.
    extraComponents = [
      "cast"
      "luci"
      "met"
      "mqtt"
      "remote_calendar"
      "rest"
      "roborock"
      "sonos"
      "template"
    ];
    config = {
      default_config = { };
      "automation ui" = "!include automations.yaml";
      "scene ui" = "!include scenes.yaml";
      "script ui" = "!include scripts.yaml";
      homeassistant = {
        name = "Home";
        time_zone = "Europe/Helsinki";
        unit_system = "metric";
        internal_url = "http://ha.home.arpa";
        external_url = "https://ha.miksu.app";
      };
      lovelace.dashboards.information-display = {
        mode = "yaml";
        filename = "ui-lovelace.yaml";
        title = "Information display";
        icon = "mdi:view-dashboard-outline";
        show_in_sidebar = true;
        require_admin = false;
      };
      # The Ray is reachable from Hestia, but SSDP discovery does not cross the
      # current Wi-Fi/Ethernet path reliably. Its DHCP reservation owns this IP.
      sonos.media_player.hosts = [ "192.168.67.220" ];

      # The Roborock app remains the schedule owner. Mirror its schedule here
      # only so the information display can show the next planned run.
      template = [
        {
          triggers = [
            {
              trigger = "homeassistant";
              event = "start";
            }
            {
              trigger = "time_pattern";
              minutes = "0";
            }
            {
              trigger = "state";
              entity_id = "weather.home";
            }
          ];
          actions = [
            {
              condition = "template";
              value_template = "{{ has_value('weather.home') }}";
            }
            {
              action = "weather.get_forecasts";
              target.entity_id = "weather.home";
              data.type = "daily";
              response_variable = "daily_weather";
            }
          ];
          sensor = [
            {
              name = "Home weather today";
              unique_id = "home_weather_today";
              default_entity_id = "sensor.home_weather_today";
              state = "{{ daily_weather['weather.home'].forecast[0].condition }}";
              attributes = {
                high_temperature = "{{ daily_weather['weather.home'].forecast[0].temperature }}";
                low_temperature = "{{ daily_weather['weather.home'].forecast[0].templow }}";
                precipitation_probability = "{{ daily_weather['weather.home'].forecast[0].precipitation_probability | default(none) }}";
                precipitation = "{{ daily_weather['weather.home'].forecast[0].precipitation | default(none) }}";
              };
            }
          ];
        }
        {
          binary_sensor = [
            {
              name = "Washing machine running";
              unique_id = "washing_machine_running";
              default_entity_id = "binary_sensor.washing_machine_running";
              device_class = "running";
              state = "{{ states('sensor.washing_machine_plug_power') | float(0) > 3 }}";
              delay_off.minutes = 5;
            }
            {
              name = "PC running";
              unique_id = "pc_running";
              default_entity_id = "binary_sensor.pc_running";
              device_class = "running";
              state = "{{ states('sensor.pc_plug_power') | float(0) > 15 }}";
              delay_off.seconds = 30;
            }
          ];
          sensor = [
            {
              name = "Exterminator next scheduled cleaning";
              unique_id = "exterminator_next_scheduled_cleaning";
              default_entity_id = "sensor.exterminator_next_scheduled_cleaning";
              device_class = "timestamp";
              icon = "mdi:calendar-clock";
              state = ''
                {% set weekday = now().weekday() %}
                {% set today_run = today_at('10:00') %}
                {% if weekday in [0, 2, 4] and now() < today_run %}
                  {% set days = 0 %}
                {% else %}
                  {% set offsets = {0: 2, 1: 1, 2: 2, 3: 1, 4: 3, 5: 2, 6: 1} %}
                  {% set days = offsets[weekday] %}
                {% endif %}
                {{ (today_run + timedelta(days=days)).isoformat() }}
              '';
            }
          ];
        }
        {
          triggers = [
            {
              trigger = "homeassistant";
              event = "start";
            }
            {
              trigger = "time_pattern";
              minutes = "/5";
            }
          ];
          actions = [
            {
              action = "calendar.get_events";
              target.entity_id = [
                "calendar.elsa_outlook"
                "calendar.mikael_gcal"
              ];
              data = {
                start_date_time = "{{ today_at().isoformat() }}";
                end_date_time = "{{ (today_at() + timedelta(days=2)).isoformat() }}";
              };
              response_variable = "household_agenda";
            }
          ];
          sensor = [
            {
              name = "Household agenda";
              unique_id = "household_agenda_today";
              default_entity_id = "sensor.household_agenda_today";
              icon = "mdi:calendar-today";
              state = "{{ (household_agenda['calendar.elsa_outlook'].events | count) + (household_agenda['calendar.mikael_gcal'].events | count) }}";
              attributes = {
                elsa_events = "{{ household_agenda['calendar.elsa_outlook'].events }}";
                mikael_events = "{{ household_agenda['calendar.mikael_gcal'].events }}";
              };
            }
          ];
        }
      ];

      rest = [
        {
          resource = "https://api.digitransit.fi/routing/v2/hsl/gtfs/v1";
          method = "POST";
          headers = {
            Content-Type = "application/json";
            digitransit-subscription-key = "!secret digitransit_api_key";
          };
          payload = digitransitQuery;
          scan_interval = 15;
          timeout = 10;
          sensor = [
            {
              name = "Pohjantori departures";
              unique_id = "pohjantori_departures";
              icon = "mdi:bus-clock";
              value_template = ''
                {{ value_json.data.stop.stoptimesWithoutPatterns
                   | selectattr('trip.route.shortName', 'in', ['111', '113'])
                   | list | count }}
              '';
              json_attributes_path = "$.data.stop";
              json_attributes = [ "stoptimesWithoutPatterns" ];
            }
          ];
        }
      ];
    };

  };

  # Home Assistant resolves !secret values from secrets.yaml next to its
  # generated configuration. The rendered file lives in /run and never in
  # the Nix store; only this symlink is placed in Home Assistant's state dir.
  sops = {
    secrets = {
      digitransit-api-key = { };
      mythos-wifi-qr-payload = {
        owner = "hass";
        group = "hass";
        mode = "0400";
      };
    };
    templates."home-assistant-secrets.yaml" = {
      owner = "hass";
      group = "hass";
      mode = "0400";
      content = ''
        digitransit_api_key: ${config.sops.placeholder.digitransit-api-key}
      '';
    };
  };

  systemd = {
    # Keep configuration.yaml declarative while allowing Home Assistant to
    # manage automations, scenes, and scripts created through the UI.
    tmpfiles.rules =
      let
        configDir = config.services.home-assistant.configDir;
      in
      [
        "f ${configDir}/automations.yaml 0600 hass hass -"
        "f ${configDir}/scenes.yaml 0600 hass hass -"
        "f ${configDir}/scripts.yaml 0600 hass hass -"
        "L+ ${configDir}/secrets.yaml - - - - ${config.sops.templates."home-assistant-secrets.yaml".path}"
      ];

    services = {
      # Restart Home Assistant when the encrypted source changes. This replaces
      # sops-nix's deprecated activation-script restartUnits mechanism.
      home-assistant.restartTriggers = [
        config.sops.secrets.digitransit-api-key.sopsFileHash
      ];

      # Generate the Wi-Fi QR code from its runtime secret. The QR payload and
      # resulting image never enter the Nix store.
      home-assistant-wifi-qr = {
        description = "Generate the Mythos Wi-Fi QR code";
        wantedBy = [ "multi-user.target" ];
        before = [ "home-assistant.service" ];
        requiredBy = [ "home-assistant.service" ];
        restartTriggers = [ config.sops.secrets.mythos-wifi-qr-payload.sopsFileHash ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "hass";
          Group = "hass";
          UMask = "0077";
        };
        script = ''
          set -euo pipefail
          install -d -m 0700 ${config.services.home-assistant.configDir}/www
          payload="$(< ${config.sops.secrets.mythos-wifi-qr-payload.path})"
          test -n "$payload"
          printf '%s' "$payload" \
            | ${pkgs.qrencode}/bin/qrencode \
                -t PNG -l Q -s 8 -m 2 \
                -o ${config.services.home-assistant.configDir}/www/mythos-wifi.png
        '';
      };
    };
  };

  # Sonos sends push updates back to Home Assistant on TCP 1400.
  networking.firewall.interfaces.enp31s0.allowedTCPPorts = [
    1400
    8123
  ];
}
