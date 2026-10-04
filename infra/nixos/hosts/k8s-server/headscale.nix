{ config, pkgs, ... }:
let
  headscalePolicy = pkgs.writeText "headscale-policy.json" (
    builtins.toJSON {
      # Personal devices remain user-owned. Infrastructure nodes are converted
      # to tag ownership only after this policy has been deployed successfully.
      tagOwners = {
        "tag:infra" = [ "mikael@" ];
        "tag:home-subnet-router" = [ "mikael@" ];
      };

      autoApprovers.routes."192.168.67.0/24" = [ "tag:home-subnet-router" ];

      acls = [
        {
          action = "accept";
          src = [ "mikael@" ];
          dst = [
            "mikael@:*"
            "tag:infra:*"
            "tag:home-subnet-router:*"
            "192.168.67.0/24:*"
          ];
        }
      ];
    }
  );
in
{
  services.headscale = {
    enable = true;
    address = "0.0.0.0"; # Needs to be reachable from K8s CNI bridge (10.42.0.1); Hetzner firewall blocks 8080 externally
    port = 8080;
    settings = {
      server_url = "https://hs.miksu.app";
      dns = {
        magic_dns = true;
        base_domain = "vpn.miksu.app";
        override_local_dns = true;
        nameservers.global = [
          "https://base.dns.mullvad.net/dns-query"
        ];
        nameservers.split."home.arpa" = [
          "192.168.67.1"
        ];
        extra_records = [
          {
            name = "argocd.miksu.app";
            type = "A";
            value = "100.64.0.1";
          }
          {
            name = "grafana.miksu.app";
            type = "A";
            value = "100.64.0.1";
          }
          {
            name = "ha.miksu.app";
            type = "A";
            value = "192.168.67.170";
          }
        ];
      };
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
      };
      policy = {
        mode = "file";
        path = headscalePolicy;
      };
      derp.server = {
        enabled = true;
        region_id = 999;
        region_code = "headscale";
        region_name = "Headscale Embedded DERP";
        stun_listen_addr = "0.0.0.0:3478";
      };
    };
  };

  services.tailscale.enable = true;

  # NixOS rollbacks do not roll back Headscale's database migrations. Keep a
  # stopped, version-specific snapshot before the newly selected binary starts.
  systemd.services.headscale.preStart = ''
    backup_dir=/var/lib/headscale/upgrade-backups/pre-${config.services.headscale.package.version}

    if [[ ! -e "$backup_dir/.complete" && -e /var/lib/headscale/db.sqlite ]]; then
      mkdir -p "$backup_dir"
      for file in \
        /var/lib/headscale/db.sqlite \
        /var/lib/headscale/db.sqlite-wal \
        /var/lib/headscale/db.sqlite-shm \
        /var/lib/headscale/*.key
      do
        [[ ! -e "$file" ]] || cp -a "$file" "$backup_dir/"
      done
      touch "$backup_dir/.complete"
    fi
  '';

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ 3478 ];
    checkReversePath = "loose";
  };

  environment.systemPackages = [ config.services.headscale.package ];
}
