{
  pkgs,
  codex,
}:
pkgs.writeShellScriptBin "codex" ''
  exec ${codex}/bin/codex \
    -c 'model_provider="hestia"' \
    -c 'model_providers.hestia={name="Hestia CLIProxyAPI",base_url="https://hestia.vpn.miksu.app:8317/v1",wire_api="responses",requires_openai_auth=false}' \
    "$@"
''
