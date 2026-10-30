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

  departures = "(state_attr('sensor.pohjantori_departures', 'stoptimesWithoutPatterns') or []) | selectattr('trip.route.shortName', 'in', ['111', '113'])";
  nextTrip = "(${departures}) | map(attribute='trip.gtfsId') | first | default(none)";

  busLiveActivity = person: {
    # Live Activity for the next bus from Pohjantori: weekday mornings from
    # 07:45 while the person is home, or whenever they leave the home Wi-Fi.
    # While they are home it rolls over to the next bus until 08:15; once they
    # have left, it ends when the bus that was next at that point leaves.
    id = "${person}_bus_live_activity";
    alias = "Notifications · ${people.${person}}'s bus";
    mode = "single";
    triggers = [
      {
        trigger = "time";
        at = "07:45:00";
        weekday = [
          "mon"
          "tue"
          "wed"
          "thu"
          "fri"
        ];
        id = "morning";
      }
      {
        trigger = "state";
        entity_id = "sensor.${phones.${person}}_ssid";
        from = homeWifi;
        id = "left";
      }
    ];
    conditions = [
      {
        condition = "template";
        value_template = "{{ trigger.id == 'left' or is_state('binary_sensor.${person}_home', 'on') }}";
      }
    ];
    actions = [
      {
        variables.left_trip = "{{ ${nextTrip} if trigger.id == 'left' else none }}";
      }
      {
        # A bus drops out of the departures once it has left the stop.
        # iOS throttles Live Activities updated much more often than this.
        repeat = {
          "while" = [
            {
              condition = "template";
              value_template = ''
                {% set trips = (${departures}) | map(attribute='trip.gtfsId') | list %}
                {{ repeat.index <= 80 and trips | count > 0
                   and (left_trip in trips if left_trip else now() < today_at('08:15')) }}
              '';
            }
          ];
          sequence = [
            {
              # Updates left_trip outside the loop too, as it already exists there.
              variables.left_trip = ''
                {{ left_trip or (${nextTrip} if not is_state('sensor.${phones.${person}}_ssid', '${homeWifi}') else none) }}
              '';
              variables.departure = "{{ (${departures}) | first }}";
            }
            {
              variables.bus = ''
                {{ departure.trip.pattern.vehiclePositions
                   | selectattr('trip.gtfsId', 'eq', departure.trip.gtfsId) | first | default(none) }}
              '';
            }
            {
              # Stops between the bus's current or next stop and Pohjantori.
              variables.stops_away = ''
                {% set stops = departure.trip.pattern.stops | map(attribute='gtfsId') | list %}
                {% set at = bus.stopRelationship.stop.gtfsId
                   if bus and bus.stopRelationship and bus.stopRelationship.stop %}
                {{ stops.index('HSL:2215221') - stops.index(at)
                   if at in stops and 'HSL:2215221' in stops else none }}
              '';
              # Straight-line GPS distance, if the sensor is on this bus and fresh.
              variables.distance_km = ''
                {{ states('sensor.next_bus_distance') | float(none)
                   if bus and state_attr('sensor.next_bus_distance', 'vehicle') == bus.vehicleId
                   and now().timestamp() - (state_attr('sensor.next_bus_distance', 'updated') | float(0)) < 60
                   else none }}
              '';
            }
            (notify phones.${person} {
              # iOS fixes the title when the activity starts, so the line
              # number goes in the critical text.
              title = "Pohjantori";
              # iOS shows the countdown in place of this line.
              message = "{{ departure.trip.route.shortName }} to {{ departure.headsign | replace(' (M)', '') }}";
              data = {
                tag = "bus";
                live_update = true;
                silent = true;
                notification_icon = "mdi:bus";
                chronometer = true;
                "when" = "{{ departure.serviceDay + departure.realtimeDeparture }}";
                # Shown next to the countdown and in the Dynamic Island.
                critical_text = ''
                  {{- departure.trip.route.shortName }} ·
                  {%- if stops_away is not none and stops_away <= 0 %} at the stop
                  {%- elif distance_km is none and stops_away is none %} location unknown
                  {%- else %} {{ [distance_km ~ ' km' if distance_km is not none,
                                  stops_away ~ (' stop' if stops_away == 1 else ' stops') if stops_away is not none]
                                 | select | join(' · ') }}{% endif %}
                '';
              };
            })
            { delay.seconds = 30; }
          ];
        };
      }
      (notify phones.${person} {
        message = "clear_notification";
        data.tag = "bus";
      })
    ];
  };
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
      (busLiveActivity "mikael")
      (busLiveActivity "elsa")
    ];
  };
}
