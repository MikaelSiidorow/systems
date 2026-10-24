{ config, pkgs, ... }:
let
  people = [
    "mikael"
    "elsa"
  ];

  historyDir = "${config.services.home-assistant.configDir}/location-history";

  # Append one fix in OwnTracks .rec format, which Dawarich and most other
  # location history tools import directly.
  logLocation = pkgs.writeShellScript "log-location" ''
    set -eu
    person=$1 tst=$2 lat=$3 lon=$4 acc=$5
    printf '%s\t*                 \t{"_type":"location","tid":"%s","tst":%d,"lat":%s,"lon":%s,"acc":%d}\n' \
      "$(${pkgs.coreutils}/bin/date -u -d "@$tst" +%Y-%m-%dT%H:%M:%SZ)" "$person" "$tst" "$lat" "$lon" "$acc" \
      >> "${historyDir}/$person.rec"
  '';
in
{
  # Home Assistant's recorder only keeps ten days. Keep every location fix the
  # companion apps report in a separate, append-only file per person.
  systemd.tmpfiles.rules = [ "d ${historyDir} 0700 hass hass -" ];

  services.home-assistant.config = {
    shell_command.log_location = "${logLocation} {{ person }} {{ tst }} {{ lat }} {{ lon }} {{ acc }}";

    "automation location_history" = [
      {
        id = "location_history_log";
        alias = "Location history · log fix";
        mode = "queued";
        triggers = map (person: {
          trigger = "state";
          entity_id = "person.${person}";
          attribute = "latitude";
          variables = { inherit person; };
        }) people;
        conditions = [
          "{{ trigger.to_state.attributes.latitude is number and trigger.to_state.attributes.longitude is number }}"
        ];
        actions = [
          {
            action = "shell_command.log_location";
            data = {
              person = "{{ person }}";
              tst = "{{ as_timestamp(trigger.to_state.last_updated) | int }}";
              lat = "{{ trigger.to_state.attributes.latitude }}";
              lon = "{{ trigger.to_state.attributes.longitude }}";
              acc = "{{ trigger.to_state.attributes.gps_accuracy | int(0) }}";
            };
          }
        ];
      }
    ];
  };
}
