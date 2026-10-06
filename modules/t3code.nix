{
  pkgs,
  inputs,
  codex ? inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex,
}:
let
  upstream = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
  runtimePkgs = inputs.llm-agents.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  # Patch cached build outputs so Electron and the web/server bundle need no rebuild.
  patched =
    pkgs.runCommand "t3code-${upstream.version}"
      {
        outputs = [
          "out"
          "desktop"
        ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        passthru = {
          inherit (upstream.unwrapped)
            version
            appName
            src
            pnpmDeps
            resourceMonitor
            ;
        };
        inherit (upstream) meta;
      }
      ''
        mkdir -p "$out" "$desktop"
        cp -r --no-preserve=mode ${upstream.unwrapped}/. "$out/"
        cp -r --no-preserve=mode ${upstream.unwrapped.desktop}/. "$desktop/"

        # Compiled equivalent of AnalyticsService.layer -> AnalyticsService.layerTest.
        # Fail on upstream changes rather than silently retaining analytics.
        substituteInPlace "$out/libexec/t3code/apps/server/dist/bin.mjs" \
          --replace-fail 'effect(AnalyticsService, make$99)' 'AnalyticsService.layerTest'

        rm "$out/bin/t3" "$desktop/bin/t3code-desktop" \
          "$desktop/libexec/t3code/apps/server"
        ln -s "$out/libexec/t3code/apps/server" "$desktop/libexec/t3code/apps/server"
        makeWrapper ${pkgs.lib.getExe runtimePkgs.nodejs_24} "$out/bin/t3" \
          --add-flags "$out/libexec/t3code/apps/server/dist/bin.mjs" \
          --set T3CODE_TELEMETRY_ENABLED false \
          --set T3CODE_OTEL_SDK_DISABLED true
        makeWrapper ${pkgs.lib.getExe runtimePkgs.electron_44} "$desktop/bin/t3code-desktop" \
          --add-flags "$desktop/libexec/t3code/apps/desktop" \
          --set T3CODE_TELEMETRY_ENABLED false \
          --set T3CODE_OTEL_SDK_DISABLED true \
          --inherit-argv0
      '';
  codexProxy = pkgs.writeShellScriptBin "codex" ''
    exec ${codex}/bin/codex \
      -c 'model_provider="hestia"' \
      -c 'model_providers.hestia={name="Hestia CLIProxyAPI",base_url="https://hestia.vpn.miksu.app:8317/v1",wire_api="responses",requires_openai_auth=false}' \
      "$@"
  '';
in
upstream.override {
  t3code-unwrapped = patched;
  providerPackages = [
    codexProxy
    pkgs.git
    pkgs.gh
  ];
}
