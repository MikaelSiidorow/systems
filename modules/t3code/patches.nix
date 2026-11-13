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
      why = "Parent Codex app-server turns to the turn span through the JSON-RPC envelope (pingdotgg/t3code#31694).";
      find = "const request = fn(\"CodexAppServerProtocol.request\")(function* (method, payload) {";
      replace = "const offerOutgoingUntraced = offerOutgoing; const request = fn(\"CodexAppServerProtocol.request\")(function* (method, payload) { const trace = method === \"turn/start\" || method === \"turn/steer\" ? yield* ${spanTrace} : void 0; const offerOutgoing = (message) => offerOutgoingUntraced(trace === void 0 ? message : { ...message, trace });";
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
