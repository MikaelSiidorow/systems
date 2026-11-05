# Work-only Claude account pool. Auth and generated keys stay on this Mac.
{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:
let
  stateDir = "${config.xdg.stateHome}/cli-proxy-api";
  clientKeyFile = "${stateDir}/client-key";
  settings = pkgs.writeText "cli-proxy-api-local.json" (
    builtins.toJSON {
      config-version = 8;
      server = {
        host = "127.0.0.1";
        port = 8317;
        # Omit body-capture middleware; ordinary access/error logging remains.
        commercial-mode = true;
      };
      management = {
        allow-remote = false;
        secret-key = "";
        disable-control-panel = true;
      };
      routing = {
        strategy = "round-robin";
        session-affinity = true;
        session-affinity-ttl = "24h";
        session-affinity-subagents = true;
        session-affinity-rebind-on = "quota";
      };
      oauth.auth-dir = "${stateDir}/auth";
    }
  );
  hub = pkgs.writeShellApplication {
    name = "cli-proxy-api-local";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
      pkgs.openssl
    ];
    text = ''
      umask 077
      state=${lib.escapeShellArg stateDir}
      mkdir -p "$state/auth"
      chmod 700 "$state" "$state/auth"
      config_tmp=$(mktemp "$state/config.XXXXXX")
      key_tmp=""
      trap 'rm -f -- "$key_tmp" "$config_tmp"' EXIT
      for key_name in client-key management-key; do
        key_tmp=$(mktemp "$state/key.XXXXXX")
        if [[ ! -e "$state/$key_name" ]]; then
          openssl rand -hex 32 > "$key_tmp"
          # Never replace a key another invocation has already created.
          ln "$key_tmp" "$state/$key_name" 2>/dev/null || test -s "$state/$key_name"
        fi
        test -s "$state/$key_name"
        chmod 600 "$state/$key_name"
        rm -f -- "$key_tmp"
      done
      # JSON is valid YAML. Keys are injected only into this private runtime file.
      jq --rawfile key "$state/client-key" \
        --rawfile management "$state/management-key" \
        '.access."api-keys" = [($key | rtrimstr("\n"))] |
         .management."secret-key" = ($management | rtrimstr("\n"))' \
        ${settings} > "$config_tmp"
      mv "$config_tmp" "$state/config.yaml"
      exec ${lib.getExe pkgs-unstable.cliproxyapi} -config "$state/config.yaml" "$@"
    '';
  };
  claudeLocal = import ../../modules/claude-proxy.nix {
    inherit pkgs clientKeyFile;
    claude = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
    name = "claude-local";
    baseUrl = "http://127.0.0.1:8317";
  };
  claudeLocalDirenv = pkgs.writeShellScriptBin "claude-local-direnv" ''
    export DIRENV_LOG_FORMAT=
    exec ${pkgs.direnv}/bin/direnv exec "$PWD" ${claudeLocal}/bin/claude-local "$@"
  '';
in
{
  home.packages = [
    hub
    claudeLocal
    claudeLocalDirenv
  ];

  # launchd must be able to open the log paths before the service starts.
  home.activation.claudeProxyState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run install -d -m 700 ${lib.escapeShellArg stateDir}
  '';

  launchd.agents.cli-proxy-api-local = {
    enable = true;
    config = {
      ProgramArguments = [ "${hub}/bin/cli-proxy-api-local" ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 10;
      ProcessType = "Background";
      Umask = 63; # 077: service logs are private too.
      StandardOutPath = "${stateDir}/stdout.log";
      StandardErrorPath = "${stateDir}/stderr.log";
    };
  };
}
