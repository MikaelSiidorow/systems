{ config, pkgs, ... }:
let
  release = "v8.0.21";
  cliProxyApi = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "cli-proxy-api";
    version = pkgs.lib.removePrefix "v" release;
    src = pkgs.fetchurl {
      url = "https://github.com/router-for-me/CLIProxyAPI/releases/download/${release}/CLIProxyAPI_${version}_linux_amd64_no-plugin.tar.gz";
      sha256 = "609e0f9d386be3bd933b9964b3f826e1a17fe5d7e2e6cf7605f755ba3db919da";
    };
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      install -Dm755 cli-proxy-api "$out/bin/cli-proxy-api"
    '';
  };
  configTemplate = pkgs.writeText "cli-proxy-api.yaml" ''
    config-version: 8
    server:
      host: "127.0.0.1"
      port: 8317
    access:
      api-keys: []
    management:
      allow-remote: false
      secret-key: "@MANAGEMENT_KEY@"
      disable-auto-update-panel: true
    # One Codex account: a cached quota cooldown has no failover target and
    # outlives manual quota resets (upstream #5639), so let OpenAI answer.
    routing:
      retry:
        request-retry: 0
      cooldown:
        disable-cooling: true
    oauth:
      auth-dir: "/var/lib/cli-proxy-api/auth"
    observability:
      logs:
        request-log: false
  '';
in
{
  environment.systemPackages = [ cliProxyApi ];

  # Headscale owns this stable address and hestia.vpn.miksu.app DNS name.
  security.acme.certs."hestia.vpn.miksu.app" = {
    dnsProvider = "cloudflare";
    dnsResolver = "1.1.1.1:53";
    credentialFiles.CF_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare-dns-api-token.path;
  };
  services.caddy.virtualHosts."https://hestia.vpn.miksu.app:8317" = {
    useACMEHost = "hestia.vpn.miksu.app";
    extraConfig = ''
      bind 100.64.0.3
      reverse_proxy 127.0.0.1:8317
    '';
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8317 ];

  users.groups.cli-proxy-api = { };
  users.users.cli-proxy-api = {
    isSystemUser = true;
    group = "cli-proxy-api";
    home = "/var/lib/cli-proxy-api";
  };

  # Caddy exposes the loopback backend only on Hestia's tailnet address.
  systemd.services.cli-proxy-api = {
    description = "CLIProxyAPI subscription gateway";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    restartTriggers = [ configTemplate ];
    preStart = ''
      set +x
      mkdir -p auth
      if [ ! -s management-key ]; then
        ${pkgs.openssl}/bin/openssl rand -hex 32 > management-key
      fi
      ${pkgs.gnused}/bin/sed "s/@MANAGEMENT_KEY@/$(cat management-key)/" ${configTemplate} > config.yaml
    '';
    serviceConfig = {
      User = "cli-proxy-api";
      Group = "cli-proxy-api";
      StateDirectory = "cli-proxy-api";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/cli-proxy-api";
      UMask = "0077";
      ExecStart = "${cliProxyApi}/bin/cli-proxy-api -config /var/lib/cli-proxy-api/config.yaml";
      Restart = "on-failure";
      RestartSec = 5;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };
}
