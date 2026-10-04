{ inputs, ... }:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = ../../../secrets/hestia.yaml;
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

    secrets.zigbee2mqtt-secret = {
      owner = "zigbee2mqtt";
      group = "zigbee2mqtt";
      mode = "0400";
      path = "/var/lib/zigbee2mqtt/secret.yaml";
    };
  };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        omitPasswordAuth = true;
        acl = [ "topic readwrite #" ];
        settings.listener_allow_anonymous = true;
      }
    ];
  };

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant.enabled = true;
      permit_join = false;

      devices = {
        "0xa4c1380ce904ffff" = {
          friendly_name = "living_room_sensor";
          description = "Living room temperature and humidity sensor";
          homeassistant.name = "Living room sensor";
        };
        "0x8c73dafffef5d7c4" = {
          friendly_name = "ac_leak_sensor";
          description = "Air conditioner water leak sensor";
          homeassistant.name = "AC leak sensor";
        };
        "0xa4c13811751affff" = {
          friendly_name = "washing_machine_plug";
          description = "Washing machine smart plug";
          homeassistant.name = "Washing machine plug";
        };
        "0xa4c1380f6c86ffff" = {
          friendly_name = "pc_plug";
          description = "PC smart plug";
          homeassistant.name = "PC plug";
        };
      };

      serial = {
        port = "/dev/serial/by-id/usb-SONOFF_SONOFF_Dongle_Plus_MG24_ea7c162edc9aef1186d2b79061ce3355-if00-port0";
        adapter = "ember";
        baudrate = 115200;
        rtscts = false;
      };

      mqtt.server = "mqtt://127.0.0.1:1883";

      advanced = {
        channel = 25;
        network_key = "!secret.yaml network_key";
        pan_id = 22648;
        ext_pan_id = [
          95
          254
          31
          226
          167
          44
          66
          51
        ];
      };

      frontend = {
        enabled = true;
        host = "0.0.0.0";
        port = 8080;
      };
    };
  };

  systemd.services.zigbee2mqtt = {
    after = [ "mosquitto.service" ];
    requires = [ "mosquitto.service" ];
  };

  networking.firewall.interfaces.enp31s0.allowedTCPPorts = [ 8080 ];
}
