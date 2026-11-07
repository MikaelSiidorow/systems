{
  pkgs,
  inputs,
  codex ? inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.codex,
  claude ? inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.default,
  # Local OTLP/HTTP endpoint for T3's own spans. Unset keeps T3's OTel SDK off.
  # Metrics and logs stay off either way, and the relay's tracing stays off
  # while T3CODE_TELEMETRY_ENABLED is false. Never set it on the work Mac.
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

        # Patches below call bundler-assigned names that shift between releases
        # (succeed$3 is Layer.succeed, void_$1 Effect.void); fail unless each is
        # still imported from the Effect chunk, and when an anchor moves.
        cli=$(echo "$out"/libexec/t3code/apps/server/dist/binCli-*.mjs)
        effect=$(grep -E '^import \{.*\} from "\./Effect-[^"]+\.mjs";$' "$cli")
        for helper in 'succeed\$3' 'void_\$1' 'map\$9' orElseSucceed currentSpan annotateCurrentSpan; do
          printf '%s\n' "$effect" | grep -qE " as $helper[,} ]" || {
            echo "t3code: expected $helper imported from Effect in $cli" >&2
            exit 1
          }
        done
        patchOnce() {
          [ "$(grep -oE "$1" "$cli" | wc -l)" = 1 ] || {
            echo "t3code: expected one '$1' in $cli" >&2
            exit 1
          }
          sed -Ei "s|$1|$2|" "$cli"
        }

        # Swap the PostHog-backed AnalyticsService layer for a no-op one, like the
        # AnalyticsService.layerTest that 0.1.6 removed. Fail on other upstream
        # changes rather than silently retaining analytics.
        patchOnce 'effect\(AnalyticsService, make\$[0-9]+\)' \
          'succeed$3(AnalyticsService, AnalyticsService.of({ record: () => void_$1, flush: void_$1, recordOwners: () => void_$1 }))'

        # Link the Claude and Codex sessions T3 starts to its turn spans; proposed
        # upstream in https://github.com/pingdotgg/t3code/discussions/31694.
        # Without otlpTracesUrl nothing is exported, so these apply everywhere.
        traceparent='`00-''${span.traceId}-''${span.spanId}-''${span.sampled ? "01" : "00"}`'
        # One trace per provider turn instead of one per server lifetime.
        patchOnce 'start: fn\("ProviderTurnStartService\.start"\)\(function\* \(input\) \{' \
          'start: fn("ProviderTurnStartService.start", { root: true })(function* (input) { yield* annotateCurrentSpan({ "orchestration_v2.thread_id": input.threadId, "orchestration_v2.run_id": input.runId });'
        # Claude keeps an explicit TRACEPARENT in its env. T3 reuses one Claude
        # process per thread, which reads it once, so later turns in a thread
        # stay under the first turn's span.
        if grep -qF 'const { mcpServers, ...queryOptions } = input.options;' "$cli"; then
          # 0.1.3; drop once llm-agents is past it.
          patchOnce 'const \{ mcpServers, \.\.\.queryOptions \} = input\.options;' \
            'const { mcpServers, ...untracedQueryOptions } = input.options; const queryOptions = yield* currentSpan.pipe(map$9((span) => ({ ...untracedQueryOptions, env: { ...(untracedQueryOptions.env ?? process.env), TRACEPARENT: '"$traceparent"' } })), orElseSucceed(() => untracedQueryOptions));'
        else
          patchOnce '\[AGENT_THREAD_ENV\]: input\.threadId' \
            '[AGENT_THREAD_ENV]: input.threadId, ...(yield* currentSpan.pipe(map$9((span) => ({ TRACEPARENT: '"$traceparent"' })), orElseSucceed(() => ({}))))'
        fi
        # Codex app-server parents a request to the JSON-RPC envelope's trace.
        patchOnce 'const request = fn\("CodexAppServerProtocol\.request"\)\(function\* \(method, payload\) \{' \
          'const offerOutgoingUntraced = offerOutgoing; const request = fn("CodexAppServerProtocol.request")(function* (method, payload) { const trace = method === "turn/start" \|\| method === "turn/steer" ? yield* currentSpan.pipe(map$9((span) => ({ traceparent: '"$traceparent"' })), orElseSucceed(() => void 0)) : void 0; const offerOutgoing = (message) => offerOutgoingUntraced(trace === void 0 ? message : { ...message, trace });'
        ${pkgs.lib.getExe runtimePkgs.nodejs_24} --check "$cli"

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
