{ config, ... }:
{
  sops.secrets.cloudflare-dns-api-token = { };

  security.acme = {
    acceptTerms = true;
    defaults.email = "mikael@siidorow.com";
    certs."ha.miksu.app" = {
      dnsProvider = "cloudflare";
      dnsResolver = "1.1.1.1:53";
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare-dns-api-token.path;
    };
  };

  services.caddy = {
    enable = true;

    virtualHosts = {
      "https://ha.miksu.app" = {
        useACMEHost = "ha.miksu.app";
        extraConfig = ''
          reverse_proxy 127.0.0.1:8123
        '';
      };

      "http://ha.home.arpa".extraConfig = ''
        reverse_proxy 127.0.0.1:8123
      '';

      "http://zigbee.home.arpa".extraConfig = ''
        reverse_proxy 127.0.0.1:8080
      '';
    };
  };

  # Keep the backend ports open during the initial rollout. Once both proxies
  # are verified, HA and Zigbee2MQTT can bind to loopback and only HTTP needs
  # to be exposed on the LAN.
  networking.firewall.interfaces = {
    enp31s0.allowedTCPPorts = [
      80
      443
    ];
    tailscale0.allowedTCPPorts = [ 443 ];
  };
}
