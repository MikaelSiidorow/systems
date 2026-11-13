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

        # Patch the server chunk that builds the runtime layer (binCli up to
        # 0.1.6, runtimeLayer from 0.1.7). Fail when an anchor moves.
        dist="$out/libexec/t3code/apps/server/dist"
        chunk=$(grep -lE 'effect\(AnalyticsService, make\$[0-9]+\)' "$dist"/*.mjs)
        [ "$(printf '%s\n' "$chunk" | wc -l)" = 1 ] || {
          echo "t3code: expected one chunk building AnalyticsService in $dist" >&2
          exit 1
        }
        patchOnce() {
          local file=''${3:-$chunk}
          [ "$(grep -oE "$1" "$file" | wc -l)" = 1 ] || {
            echo "t3code: expected one '$1' in $file" >&2
            exit 1
          }
          sed -Ei "s|$1|$2|" "$file"
        }
        # Import the Effect helpers the patches call under our own names. Import
        # aliases shift between releases, but the Effect chunk keeps effect's
        # own names, under a comment naming each effect/dist module.
        effectChunk=$(grep -oE '^import \{.*\} from "\./Effect-[^"]+\.mjs";$' "$chunk" | grep -oE 'Effect-[^"]+\.mjs')
        imports=""
        for helper in Layer.js:succeed:t3pLayerSucceed Effect.js:void_:t3pVoid Effect.js:map:t3pMap \
          Effect.js:orElseSucceed:t3pOrElseSucceed Effect.js:currentSpan:t3pCurrentSpan \
          Effect.js:annotateCurrentSpan:t3pAnnotateCurrentSpan; do
          IFS=: read -r module name local <<< "$helper"
          defined=$(awk -v module="$module" -v name="$name" '
            /^\/\/ .*\/effect\/dist\// { section = $0; sub(/.*\/effect\/dist\//, "", section) }
            section == module && match($0, "^(const|function) " name "(\\$[0-9]+)?[ (=]") {
              print substr($0, RSTART, RLENGTH)
            }' "$dist/$effectChunk" | sed -E 's/^(const|function) //; s/[ (=]$//')
          alias=$(grep -oE "(^|[{[:space:],])$(printf '%s' "$defined" | sed 's/\$/\\$/g') as [A-Za-z0-9_\$]+[,} ]" "$dist/$effectChunk" | sed -E 's/.* as //; s/[,} ]$//')
          [ "$(printf '%s\n' "$defined" | wc -l)" = 1 ] && [ -n "$defined" ] \
            && [ "$(printf '%s\n' "$alias" | wc -l)" = 1 ] && [ -n "$alias" ] \
            && ! grep -q "$local" "$chunk" || {
            echo "t3code: cannot import $module $name from $effectChunk as $local" >&2
            exit 1
          }
          imports="$imports''${imports:+, }$alias as $local"
        done
        # The chunk ends in a sourceMappingURL comment without a newline.
        printf '\nimport { %s } from "./%s";\n' "$imports" "$effectChunk" >> "$chunk"

        # Swap the PostHog-backed AnalyticsService layer for a no-op one, like the
        # AnalyticsService.layerTest that 0.1.6 removed. Fail on other upstream
        # changes rather than silently retaining analytics.
        patchOnce 'effect\(AnalyticsService, make\$[0-9]+\)' \
          't3pLayerSucceed(AnalyticsService, AnalyticsService.of({ record: () => t3pVoid, flush: t3pVoid, recordOwners: () => t3pVoid }))'

        # Link the Claude and Codex sessions T3 starts to its turn spans; proposed
        # upstream in https://github.com/pingdotgg/t3code/discussions/31694.
        # Without otlpTracesUrl nothing is exported, so these apply everywhere.
        traceparent='`00-''${span.traceId}-''${span.spanId}-''${span.sampled ? "01" : "00"}`'
        spanTrace='t3pCurrentSpan.pipe(t3pMap((span) => ({ traceparent: '"$traceparent"' })), t3pOrElseSucceed(() => void 0))'
        # One trace per provider turn instead of one per server lifetime.
        patchOnce 'start: fn\("ProviderTurnStartService\.start"\)\(function\* \(input\) \{' \
          'start: fn("ProviderTurnStartService.start", { root: true })(function* (input) { yield* t3pAnnotateCurrentSpan({ "orchestration_v2.thread_id": input.threadId, "orchestration_v2.run_id": input.runId });'
        # Claude keeps an explicit TRACEPARENT in its env. T3 reuses one Claude
        # process per thread, which reads it once, so later turns in a thread
        # stay under the first turn's span.
        if grep -qF 'const { mcpServers, ...queryOptions } = input.options;' "$chunk"; then
          # 0.1.3; drop once llm-agents is past it.
          patchOnce 'const \{ mcpServers, \.\.\.queryOptions \} = input\.options;' \
            'const { mcpServers, ...untracedQueryOptions } = input.options; const trace = yield* '"$spanTrace"'; const queryOptions = trace === void 0 ? untracedQueryOptions : { ...untracedQueryOptions, env: { ...(untracedQueryOptions.env ?? process.env), TRACEPARENT: trace.traceparent } };'
        else
          patchOnce '\[AGENT_THREAD_ENV\]: input\.threadId' \
            '[AGENT_THREAD_ENV]: input.threadId, ...(yield* '"$spanTrace"'.pipe(t3pMap((trace) => trace === void 0 ? {} : { TRACEPARENT: trace.traceparent })))'
        fi
        # Codex app-server parents a request to the JSON-RPC envelope's trace.
        patchOnce 'const request = fn\("CodexAppServerProtocol\.request"\)\(function\* \(method, payload\) \{' \
          'const offerOutgoingUntraced = offerOutgoing; const request = fn("CodexAppServerProtocol.request")(function* (method, payload) { const trace = method === "turn/start" \|\| method === "turn/steer" ? yield* '"$spanTrace"' : void 0; const offerOutgoing = (message) => offerOutgoingUntraced(trace === void 0 ? message : { ...message, trace });'
        # The prompt names "its task ID", so agents that skip loading the schema
        # call t3_background_wait with taskId or nothing and fail once.
        patchOnce 'with its task ID before you end your turn' \
          'with its task ID in \\`taskIds\\` (an array) before you end your turn'
        ${pkgs.lib.getExe runtimePkgs.nodejs_24} --check "$chunk"

        # Wake a PR-watching thread for new comments, not edits. Review bots
        # rewrite their summary comments in place, and each rewrite resumed a
        # long thread from a cold cache.
        activeAt='const activeAt = \(remark\) => remark\.editedAt \?\? remark\.createdAt;'
        watchChunk=$(grep -lE "$activeAt" "$dist"/*.mjs)
        [ "$(printf '%s\n' "$watchChunk" | wc -l)" = 1 ] || {
          echo "t3code: expected one chunk watching PR remarks in $dist" >&2
          exit 1
        }
        patchOnce "$activeAt" 'const activeAt = (remark) => remark.createdAt;' "$watchChunk"
        ${pkgs.lib.getExe runtimePkgs.nodejs_24} --check "$watchChunk"

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
