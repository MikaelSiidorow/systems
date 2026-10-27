{
  pkgs,
  inputs,
  codex ? inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex,
  claude ? inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default,
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
        cp -r --preserve=mode ${upstream.unwrapped}/. "$out/"
        cp -r --preserve=mode ${upstream.unwrapped.desktop}/. "$desktop/"
        chmod -R u+w "$out" "$desktop"

        # Compiled equivalent of AnalyticsService.layer -> AnalyticsService.layerTest.
        # The make$N suffix is a bundler-assigned name that shifts between releases.
        # Fail on other upstream changes rather than silently retaining analytics.
        analytics='effect\(AnalyticsService, make\$[0-9]+\)'
        cli=$(echo "$out"/libexec/t3code/apps/server/dist/binCli-*.mjs)
        [ "$(grep -cE "$analytics" "$cli")" = 1 ] || {
          echo "t3code: expected one '$analytics' in $cli" >&2
          exit 1
        }
        sed -Ei "s/$analytics/AnalyticsService.layerTest/" "$cli"

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
  direnvWrapper =
    name: executable:
    pkgs.writeShellScriptBin name ''
      export DIRENV_LOG_FORMAT=
      exec ${pkgs.direnv}/bin/direnv exec "$PWD" ${executable} "$@"
    '';
  direnvProviders = [
    (direnvWrapper "codex-direnv" "${codex}/bin/codex")
    (direnvWrapper "claude-direnv" "${claude}/bin/claude")
  ];
in
(upstream.override {
  t3code-unwrapped = patched;
  providerPackages = [
    codex
    claude
    pkgs.git
    pkgs.git-lfs
    pkgs.gh
  ]
  ++ direnvProviders;
}).overrideAttrs
  (previous: {
    passthru = previous.passthru // {
      inherit direnvProviders;
    };
  })
