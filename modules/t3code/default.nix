{
  pkgs,
  inputs,
  codex ? inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex,
  claude ? inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default,
  # Antigravity CLI, on hosts that run it. Unset leaves T3 without it.
  antigravity ? null,
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
    name: executable: preamble:
    pkgs.writeShellScriptBin name ''
      ${preamble}
      export DIRENV_LOG_FORMAT=
      # A blocked or broken .envrc makes `direnv exec` exit before the agent
      # starts, which T3 reports only as exit code 1. Run without it instead.
      if ${pkgs.direnv}/bin/direnv exec "$PWD" ${pkgs.coreutils}/bin/true >/dev/null 2>&1; then
        exec ${pkgs.direnv}/bin/direnv exec "$PWD" ${executable} "$@"
      fi
      echo "${name}: direnv could not load $PWD; starting without it" >&2
      exec ${executable} "$@"
    '';
  direnvProviders = [
    (direnvWrapper "codex-direnv" "${codex}/bin/codex" "")
    (direnvWrapper "claude-direnv" "${claude}/bin/claude" "")
  ]
  # T3 runs only an executable named agy or antigravity as `agy acp`, so this
  # wrapper cannot follow the -direnv naming.
  ++ pkgs.lib.optional (antigravity != null) (
    direnvWrapper "antigravity" "${antigravity}/bin/agy" ''
      # T3's sign-in sets BROWSER to a helper that shows the Google link in
      # its UI, but agy refuses to call BROWSER without a display, so sign-in
      # failed on headless Hestia.
      if [ -n "''${BROWSER:-}" ] && [ -z "''${DISPLAY:-}''${WAYLAND_DISPLAY:-}" ]; then
        export DISPLAY=:0
      fi
    ''
  );
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
