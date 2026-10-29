let
  homeWifi = "Mythos";

  # Companion app entities are named after the device name each phone
  # registered with, so renaming a phone in the app changes them.
  phones = {
    mikael = "mikaels_iphone";
    elsa = "nl_fy712fq9gj";
  };

  people = {
    mikael = "Mikael";
    elsa = "Elsa";
  };

  notify = phone: data: {
    action = "notify.mobile_app_${phone}";
    inherit data;
    # One unreachable phone should not stop the other from being notified.
    continue_on_error = true;
  };

  # Home if either GPS or the home Wi-Fi says so. The off delay hides the short
  # GPS flaps seen around the building and Wi-Fi drops while the phone sleeps.
  presence = person: {
    name = "${people.${person}} home";
    unique_id = "${person}_home";
    default_entity_id = "binary_sensor.${person}_home";
    device_class = "presence";
    state = ''
      {{ is_state('person.${person}', 'home')
         or is_state('sensor.${phones.${person}}_ssid', '${homeWifi}') }}
    '';
    delay_off.minutes = 15;
  };

  arrivedHome = person: notifyWho: {
    id = "${person}_arrived_home";
    alias = "Notifications · ${person} arrived home";
    mode = "single";
    triggers = [
      {
        trigger = "state";
        entity_id = "binary_sensor.${person}_home";
        from = "off";
        to = "on";
      }
    ];
    actions = [
      (notify phones.${notifyWho} {
        title = "${people.${person}} is home";
        message = "${people.${person}} just arrived home.";
      })
    ];
  };

  departures = "state_attr('sensor.pohjantori_departures', 'stoptimesWithoutPatterns') or []";
  trackedDeparture = "(${departures}) | selectattr('trip.gtfsId', 'eq', trip_id) | first | default(none)";
in
{
  services.home-assistant.config = {
    template = [
      {
        binary_sensor = map presence (builtins.attrNames phones);
      }
    ];

    "automation notifications" = [
      (arrivedHome "mikael" "elsa")
      (arrivedHome "elsa" "mikael")
      {
        id = "laundry_done";
        alias = "Notifications · laundry done";
        mode = "single";
        triggers = [
          {
            trigger = "state";
            entity_id = "binary_sensor.washing_machine_running";
            from = "on";
            to = "off";
          }
        ];
        actions = map (
          phone:
          notify phone {
            title = "Laundry done";
            message = "The washing machine has finished.";
            data.tag = "laundry";
          }
        ) (builtins.attrValues phones);
      }
      {
        # Live Activity for the next bus after Mikael leaves the home Wi-Fi,
        # tracked until it leaves the stop.
        id = "mikael_bus_live_activity";
        alias = "Notifications · Mikael's bus";
        mode = "single";
        triggers = [
          {
            trigger = "state";
            entity_id = "sensor.${phones.mikael}_ssid";
            from = homeWifi;
          }
        ];
        actions = [
          {
            variables.trip_id = ''
              {{ (${departures}) | selectattr('trip.route.shortName', 'in', ['111', '113'])
                 | map(attribute='trip.gtfsId') | first | default(none) }}
            '';
          }
          {
            condition = "template";
            value_template = "{{ trip_id is not none }}";
          }
          {
            # The bus drops out of the departures once it has left the stop.
            # One update a minute stays well inside iOS's Live Activity budget.
            repeat = {
              "while" = [
                {
                  condition = "template";
                  value_template = "{{ (${trackedDeparture}) is not none and repeat.index <= 20 }}";
                }
              ];
              sequence = [
                {
                  variables.departure = "{{ ${trackedDeparture} }}";
                }
                {
                  # Vehicle coordinates can be null in OTP, so distance() may too.
                  variables.distance_km = ''
                    {% set bus = departure.trip.pattern.vehiclePositions
                       | selectattr('trip.gtfsId', 'eq', trip_id) | first | default(none) %}
                    {% set stop = states.sensor.pohjantori_departures.attributes %}
                    {% set km = distance(bus.lat, bus.lon, stop.lat, stop.lon)
                       if bus and bus.lat is not none and bus.lon is not none %}
                    {{ km | round(1) if km is number else none }}
                  '';
                }
                (notify phones.mikael {
                  title = "{{ departure.trip.route.shortName }} to {{ departure.headsign | replace(' (M)', '') }}";
                  # iOS shows the countdown in place of this line.
                  message = "{{ (departure.serviceDay + departure.realtimeDeparture) | timestamp_custom('%H.%M') }}";
                  data = {
                    tag = "bus";
                    live_update = true;
                    silent = true;
                    notification_icon = "mdi:bus";
                    chronometer = true;
                    "when" = "{{ departure.serviceDay + departure.realtimeDeparture }}";
                    # Shown next to the countdown and in the Dynamic Island.
                    critical_text = "{{ distance_km ~ ' km' if distance_km is not none else 'location unknown' }}";
                  };
                })
                { delay.minutes = 1; }
              ];
            };
          }
          (notify phones.mikael {
            message = "clear_notification";
            data.tag = "bus";
          })
        ];
      }
    ];
  };
}
