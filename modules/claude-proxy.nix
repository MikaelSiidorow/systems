{
  pkgs,
  claude,
  name ? "claude-hestia",
}:
let
  # --settings overrides user/project env; exports carry routing to children.
  settings = pkgs.writeText "claude-hestia-settings.json" (
    builtins.toJSON {
      env = {
        ANTHROPIC_BASE_URL = "https://hestia.vpn.miksu.app:8317";
        # Access is restricted to the tailnet; the proxy has no client API keys.
        ANTHROPIC_AUTH_TOKEN = "hestia-tailnet";
        # unset only clears the shell; settings could restore a saved key.
        ANTHROPIC_API_KEY = "";
        CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
      };
    }
  );
in
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = [
    pkgs.jq
    pkgs.coreutils
  ];
  text = ''
    export ANTHROPIC_BASE_URL=https://hestia.vpn.miksu.app:8317
    export ANTHROPIC_AUTH_TOKEN=hestia-tailnet
    unset ANTHROPIC_API_KEY
    export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
    args=()
    extra_settings='{}'
    while (( $# )); do
      case "$1" in
        --settings)
          if (( $# < 2 )); then
            echo '--settings requires a file or JSON object' >&2
            exit 2
          fi
          extra_settings="$2"
          shift 2
          ;;
        --settings=*)
          extra_settings="''${1#--settings=}"
          shift
          ;;
        --)
          args+=("$@")
          break
          ;;
        *)
          args+=("$1")
          shift
          ;;
      esac
    done

    # T3's SDK passes its own --settings. Merge it rather than letting the
    # CLI's last argument replace the proxy overlay (or discard SDK options).
    umask 077
    merged_settings=$(mktemp)
    trap 'rm -f -- "$merged_settings"' EXIT
    if [[ -f "$extra_settings" ]]; then
      jq --slurpfile proxy ${settings} '. * $proxy[0]' "$extra_settings" > "$merged_settings"
    else
      printf '%s' "$extra_settings" | jq --slurpfile proxy ${settings} '. * $proxy[0]' > "$merged_settings"
    fi

    ${claude}/bin/claude --settings "$merged_settings" "''${args[@]}" <&0 &
    claude_pid=$!
    trap 'kill -TERM "$claude_pid" 2>/dev/null || true; exit 143' TERM
    trap 'kill -INT "$claude_pid" 2>/dev/null || true; exit 130' INT
    trap 'kill -HUP "$claude_pid" 2>/dev/null || true; exit 129' HUP
    wait "$claude_pid"
  '';
}
