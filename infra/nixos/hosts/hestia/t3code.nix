{
  pkgs,
  inputs,
  username,
  ...
}:
let
  t3code = import ../../../../modules/t3code.nix {
    inherit pkgs inputs;
    claude = claudeCode;
  };
  claudeCode = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
  pair = pkgs.writeShellApplication {
    name = "t3-hestia-pair";
    runtimeInputs = [
      t3code
      pkgs.gnused
    ];
    text = ''
      t3 pair "$@" | sed -n 's|^Pairing URL: http://127.0.0.1:3773|https://hestia.vpn.miksu.app:3773|p'
    '';
  };
in
{
  environment.systemPackages = [
    t3code
    pair
    claudeCode
    pkgs.ghostty.terminfo
  ];

  services.caddy.virtualHosts."https://hestia.vpn.miksu.app:3773" = {
    useACMEHost = "hestia.vpn.miksu.app";
    extraConfig = ''
      bind 100.64.0.3
      reverse_proxy 127.0.0.1:3773
    '';
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3773 ];

  systemd.services.t3code = {
    description = "T3 Code agent server";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "cli-proxy-api.service"
    ];
    wants = [ "network-online.target" ];
    path = [
      claudeCode
      pkgs.git
      pkgs.gh
      pkgs.openssh
      pkgs.ripgrep
    ];
    environment.HOME = "/home/${username}";
    serviceConfig = {
      User = username;
      WorkingDirectory = "/home/${username}";
      ExecStart = "${t3code}/bin/t3 serve --host 127.0.0.1 --port 3773";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
      # Headless startup prints a pairing credential; keep it out of the journal.
      StandardOutput = "null";
    };
  };
}
