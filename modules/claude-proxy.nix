{
  pkgs,
  claude,
  name ? "claude-hestia",
  baseUrl ? "https://hestia.vpn.miksu.app:8317",
  # A local client key uses a custom header, preserving the claude.ai login.
  clientKeyFile ? null,
}:
let
  # --settings overrides user/project env; exports carry routing to children.
  settings = pkgs.writeText "${name}-settings.json" (
    builtins.toJSON {
      env = {
        ANTHROPIC_BASE_URL = baseUrl;
        # Hestia uses tailnet access; the local proxy uses a custom header.
        ANTHROPIC_AUTH_TOKEN = if clientKeyFile == null then "hestia-tailnet" else "";
        # unset only clears the shell; settings could restore a saved key.
        ANTHROPIC_API_KEY = "";
        CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY = "1";
        # A model newer than this build would get an assumed 200K window and
        # compact early; let the API's real limit decide instead.
        CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT = "1";
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
    export ANTHROPIC_BASE_URL=${pkgs.lib.escapeShellArg baseUrl}
    ${
      if clientKeyFile == null then
        "export ANTHROPIC_AUTH_TOKEN=hestia-tailnet"
      else
        ''
          unset ANTHROPIC_AUTH_TOKEN
          if [[ ! -s ${pkgs.lib.escapeShellArg clientKeyFile} ]]; then
            echo 'Local proxy key missing; start cli-proxy-api-local first.' >&2
            exit 1
          fi
          ANTHROPIC_CUSTOM_HEADERS="X-Api-Key: $(cat ${pkgs.lib.escapeShellArg clientKeyFile})"
          export ANTHROPIC_CUSTOM_HEADERS
        ''
    }
    unset ANTHROPIC_API_KEY
    export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=1
    export CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1
    args=()
    extra_settings='{}'
    while (( $# )); do
      case "$1" in
        --add-dir|--agent|--agents|--allowedTools|--allowed-tools|\
        --append-system-prompt|--append-system-prompt-file|--autocompact|\
        --betas|--debug-file|--disallowedTools|--disallowed-tools|--effort|\
        --environment|--fallback-model|--file|--input-format|--json-schema|\
        --max-budget-usd|--max-turns|--mcp-config|--model|-n|--name|\
        --output-format|--permission-mode|--permission-prompts|--plugin-dir|\
        --plugin-url|--remote-control-session-name-prefix|--session-id|\
        --setting-sources|--system-prompt|--system-prompt-file|\
        --system-prompt-snapshot|--tools)
          # Required option values may themselves be literal --settings or --.
          args+=("$1")
          shift
          if (( $# )); then
            args+=("$1")
            shift
          fi
          ;;
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
    ${pkgs.lib.optionalString (clientKeyFile != null) ''
      # Keep the client key out of the Nix store and override project routing.
      local_settings=$(mktemp)
      trap 'rm -f -- "$merged_settings" "$local_settings"' EXIT
      jq --rawfile key ${pkgs.lib.escapeShellArg clientKeyFile} \
        '.env.ANTHROPIC_CUSTOM_HEADERS = ("X-Api-Key: " + ($key | rtrimstr("\n")))' \
        "$merged_settings" > "$local_settings"
      mv "$local_settings" "$merged_settings"
    ''}

    ${claude}/bin/claude --settings "$merged_settings" "''${args[@]}" <&0 &
    claude_pid=$!
    trap 'kill -TERM "$claude_pid" 2>/dev/null || true; exit 143' TERM
    trap 'kill -INT "$claude_pid" 2>/dev/null || true; exit 130' INT
    trap 'kill -HUP "$claude_pid" 2>/dev/null || true; exit 129' HUP
    wait "$claude_pid"
  '';
}
