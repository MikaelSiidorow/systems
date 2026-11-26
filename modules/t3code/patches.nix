# Edits to T3's built server bundle, applied by apply-patches.mjs. Each `find`
# must occur exactly once across the bundle, so the build fails when upstream
# moves an anchor. `find` is literal unless `regex = true`. Drop a patch once
# upstream ships its fix.
let
  # The current Effect span as a W3C traceparent, or undefined outside a span.
  spanTrace = "t3pCurrentSpan.pipe(t3pMap((span) => ({ traceparent: `00-\${span.traceId}-\${span.spanId}-\${span.sampled ? \"01\" : \"00\"}` })), t3pOrElseSucceed(() => void 0))";
in
{
  # Effect exports the patches call, as local name = "module:export". The
  # bundle renames these between releases, so the script resolves each from
  # the Effect chunk and imports it into every file that uses it.
  helpers = {
    t3pLayerSucceed = "Layer.js:succeed";
    t3pVoid = "Effect.js:void_";
    t3pMap = "Effect.js:map";
    t3pOrElseSucceed = "Effect.js:orElseSucceed";
    t3pCurrentSpan = "Effect.js:currentSpan";
    t3pAnnotateCurrentSpan = "Effect.js:annotateCurrentSpan";
    t3pFnUntraced = "Effect.js:fnUntraced";
  };

  patches = [
    {
      why = "Swap the PostHog-backed AnalyticsService for a no-op, like the layerTest 0.1.6 removed.";
      find = "effect\\(AnalyticsService, make\\$[0-9]+\\)";
      regex = true;
      replace = "t3pLayerSucceed(AnalyticsService, AnalyticsService.of({ record: () => t3pVoid, flush: t3pVoid, recordOwners: () => t3pVoid }))";
    }
    {
      why = "One trace per provider turn instead of one per server lifetime (pingdotgg/t3code#31694).";
      find = "start: fn(\"ProviderTurnStartService.start\")(function* (input) {";
      replace = "start: fn(\"ProviderTurnStartService.start\", { root: true })(function* (input) { yield* t3pAnnotateCurrentSpan({ \"orchestration_v2.thread_id\": input.threadId, \"orchestration_v2.run_id\": input.runId });";
    }
    {
      # T3 reuses one Claude process per thread, which reads TRACEPARENT once,
      # so later turns in a thread stay under the first turn's span.
      why = "Parent Claude sessions to the turn span (pingdotgg/t3code#31694).";
      find = "[AGENT_THREAD_ENV]: input.threadId";
      replace = "[AGENT_THREAD_ENV]: input.threadId, ...(yield* ${spanTrace}.pipe(t3pMap((trace) => trace === void 0 ? {} : { TRACEPARENT: trace.traceparent })))";
    }
    {
      # Antigravity's ACP process also lives for the whole thread, so as with
      # Claude its hooks parent every turn to the first turn's span.
      why = "Give Antigravity the turn span its OTel hook reads; T3 passes it the thread ID but not the trace.";
      find = "prepareSpawn\\(runtimeInput\\.cwd, threadEnvironment === void 0 \\? processEnvironment : \\{\\s*\\.\\.\\.processEnvironment,\\s*\\.\\.\\.threadEnvironment\\s*\\}\\)";
      regex = true;
      replace = "prepareSpawn(runtimeInput.cwd, { ...processEnvironment, ...(threadEnvironment ?? {}), ...(yield* ${spanTrace}.pipe(t3pMap((trace) => trace === void 0 ? {} : { TRACEPARENT: trace.traceparent }))) })";
    }
    {
      why = "Parent Codex app-server turns to the turn span through the JSON-RPC envelope (pingdotgg/t3code#31694).";
      find = "const request = fn(\"CodexAppServerProtocol.request\")(function* (method, payload) {";
      replace = "const offerOutgoingUntraced = offerOutgoing; const request = fn(\"CodexAppServerProtocol.request\")(function* (method, payload) { const trace = method === \"turn/start\" || method === \"turn/steer\" ? yield* ${spanTrace} : void 0; const offerOutgoing = (message) => offerOutgoingUntraced(trace === void 0 ? message : { ...message, trace });";
    }
    {
      # The agent's own telemetry carries no T3 thread, and later Claude turns
      # stay in turn 1's trace. T3 picks Claude's session ID, so record it on
      # every turn's span. clearedNativeSessions holds the ID Claude reported
      # when it differs (after the open retry below).
      why = "Map each T3 thread to Claude's session.id on every turn.";
      find = "const startTurn = fn\\(\"ClaudeAdapterV2\\.startTurn\"\\)\\(function\\* \\(turnInput\\) \\{\\s*modelCatalog = yield\\* loadModelCatalog;\\s*const startedAt = yield\\* now;\\s*const nativeThreadId = yield\\* getNativeThreadId\\(turnInput\\.providerThread\\);";
      regex = true;
      replace = "const startTurn = fn(\"ClaudeAdapterV2.startTurn\")(function* (turnInput) { modelCatalog = yield* loadModelCatalog; const startedAt = yield* now; const nativeThreadId = yield* getNativeThreadId(turnInput.providerThread); yield* t3pAnnotateCurrentSpan({ \"orchestration_v2.thread_id\": turnInput.threadId, \"claude.session_id\": clearedNativeSessions.get(nativeThreadId) ?? nativeThreadId });";
    }
    {
      # A first turn's startTurn span still has the original ID.
      why = "Record the new Claude session ID when open retries after an MCP registration timeout.";
      find = "const sessionId = yield* random.uuidV4();\n\t\t\t\treturn yield* openQuery({";
      replace = "const sessionId = yield* random.uuidV4(); yield* t3pAnnotateCurrentSpan({ \"claude.session_id\": sessionId });\n\t\t\t\treturn yield* openQuery({";
    }
    {
      # Codex's shared app-server records no request field but the trace
      # context on its spans or events; its thread ID is conversation.id.
      why = "Map each T3 thread to Codex's conversation.id on every turn.";
      find = "const startNativeTurn = fn\\(\"CodexAdapterV2\\.startNativeTurn\"\\)\\(function\\* \\(turnInput, codexInput\\) \\{\\s*const threadId = yield\\* getNativeThreadId\\(turnInput\\.providerThread\\);";
      regex = true;
      replace = "const startNativeTurn = fn(\"CodexAdapterV2.startNativeTurn\")(function* (turnInput, codexInput) { const threadId = yield* getNativeThreadId(turnInput.providerThread); yield* t3pAnnotateCurrentSpan({ \"orchestration_v2.thread_id\": turnInput.threadId, \"codex.conversation_id\": threadId });";
    }
  ]
  # About a third of T3's spans (upstream t3code#28196). Their children parent
  # to the caller instead.
  ++
    map
      (name: {
        why = "Stop tracing ${name}, which T3 runs constantly.";
        find = "fn(\"${name}\")(";
        replace = "t3pFnUntraced(";
      })
      [
        "NonBlockingSpawner.spawn"
        "ClaudeAgentSdkQueryRunner.trackDescendants"
      ]
  ++ [
    {
      # Its annotation would otherwise land on the caller, such as a turn span.
      why = "Stop tracing processRunner.runProcessCore, which T3 runs constantly.";
      find = "fn(\"processRunner.runProcessCore\")(function* (spawner, input) {\n\tyield* annotateCurrentSpan(\"process.command\", commandName(input.command));";
      replace = "t3pFnUntraced(function* (spawner, input) {";
    }
    {
      why = "Name taskIds in the background-wait prompt; agents that skip the schema call t3_background_wait with taskId or nothing.";
      find = "with its task ID before you end your turn";
      replace = "with its task ID in \\`taskIds\\` (an array) before you end your turn";
    }
    {
      why = "Wake PR watches for new comments, not edits; review bots rewrite their summaries in place (pingdotgg/t3code#36046).";
      find = "const activeAt = (remark) => remark.editedAt ?? remark.createdAt;";
      replace = "const activeAt = (remark) => remark.createdAt;";
    }
  ];
}
