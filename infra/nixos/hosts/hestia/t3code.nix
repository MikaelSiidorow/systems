{
  pkgs,
  inputs,
  username,
  ...
}:
let
  t3code = import ../../../../modules/t3code {
    inherit pkgs inputs;
    # Alloy keeps only the turn spans; see monitoring.nix.
    otlpTracesUrl = "http://127.0.0.1:4318/v1/traces";
    # T3 runs both providers through this host's CLIProxyAPI.
    codex = import ../../../../modules/codex-proxy.nix {
      inherit pkgs;
      codex = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex;
    };
    claude = import ../../../../modules/claude-proxy.nix {
      inherit pkgs;
      claude = claudeCode;
      name = "claude";
    };
  };
  # Run Claude Code's native build, which updates itself, so a new model works
  # without a pin bump and a Hestia deploy. The pinned build only installs it.
  claudeInstaller = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
  claudeCode = pkgs.writeShellApplication {
    name = "claude";
    text = ''
      native="$HOME/.local/bin/claude"
      # T3 reads the agent's stdout, so keep the installer off it.
      [[ -x $native ]] || ${claudeInstaller}/bin/claude install latest >&2
      exec "$native" "$@"
    '';
  };
  claudeHestia = import ../../../../modules/claude-proxy.nix {
    inherit pkgs;
    claude = claudeCode;
  };
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
    claudeHestia
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
      # Agents run solvers and builds that took the 15G host to OOM and
      # starved zigbee2mqtt. Throttle them first, and on OOM kill only the
      # offending process rather than every agent session.
      MemoryHigh = "9G";
      MemoryMax = "11G";
      OOMPolicy = "continue";
    };
  };

  # T3 runs Claude headless, so don't count on its own update check.
  systemd.services.claude-update = {
    description = "Update the native Claude Code build";
    startAt = "daily";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment.HOME = "/home/${username}";
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "${claudeCode}/bin/claude update";
    };
  };
}
