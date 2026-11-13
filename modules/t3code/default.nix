{
  pkgs,
  inputs,
  codex ? inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex,
  claude ? inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default,
  # Local OTLP/HTTP endpoint for T3's own spans. Unset keeps T3's OTel SDK off.
  # Metrics and logs stay off either way, and the relay's tracing stays off
  # while T3CODE_TELEMETRY_ENABLED is false. On the work Mac, only ever its local
  # collector.
  otlpTracesUrl ? null,
}:
let
  upstream = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.t3code;
  runtimePkgs = inputs.llm-agents.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  telemetryFlags = pkgs.lib.escapeShellArgs (
    [
      "--set"
      "T3CODE_TELEMETRY_ENABLED"
      "false"
      "--set"
      "T3CODE_OTEL_SDK_DISABLED"
      (if otlpTracesUrl == null then "true" else "false")
    ]
    ++ pkgs.lib.optionals (otlpTracesUrl != null) [
      "--set"
      "T3CODE_OTLP_TRACES_URL"
      otlpTracesUrl
    ]
  );
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

        ${pkgs.lib.getExe runtimePkgs.nodejs_24} ${./apply-patches.mjs} \
          "$out/libexec/t3code/apps/server/dist" ${pkgs.writeText "t3code-patches.json" (builtins.toJSON (import ./patches.nix))}

        rm "$out/bin/t3" "$desktop/bin/t3code-desktop" \
          "$desktop/libexec/t3code/apps/server"
        ln -s "$out/libexec/t3code/apps/server" "$desktop/libexec/t3code/apps/server"
        makeWrapper ${pkgs.lib.getExe runtimePkgs.nodejs_24} "$out/bin/t3" \
          --add-flags "$out/libexec/t3code/apps/server/dist/bin.mjs" \
          ${telemetryFlags}
        makeWrapper ${pkgs.lib.getExe runtimePkgs.electron_44} "$desktop/bin/t3code-desktop" \
          --add-flags "$desktop/libexec/t3code/apps/desktop" \
          ${telemetryFlags} \
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
