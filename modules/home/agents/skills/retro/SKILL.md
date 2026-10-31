---
name: retro
description: Find improvements to the agent environment from a coding session or PR review.
disable-model-invocation: true
---

# Retro

Suggest improvements to the coding agent's environment so future runs go better. Read `writing-for-agents` before proposing instruction changes.

## 1. Evidence

Read the primary sources for the session or PR the user names; default to the current session.

- **Session:** read the transcript or available session logs, corrections, tool failures and resulting changes.
- **PR review:** read the intent, original diff, review threads, check results and fix commits. Validate findings against the code; distinguish real misses from false positives and out-of-scope suggestions. Identify why implementation, checks or review missed each valid issue.

Done when each candidate has a concrete example and its source. State gaps in the available evidence.

## 2. Improvements

Look for candidates in these categories:

- **Navigation:** slow searches, hidden dependencies or missing pointers to existing docs.
- **Automated checks:** mistakes lint, types or tests could catch. Read the repo's check commands, hooks and CI first; an existing check that is unwired or broken is the finding. Missing automated checks are also a candidate.
- **Coding standards:** mechanical rules belong in deterministic checks. Reserve written review standards for judgment calls; place them with the reviewer, where context pressure is lower.
- **Steering files:** oversized repo or global `AGENTS.md`/`CLAUDE.md`, redundant instructions or rules that do not change behavior. Keep navigation pointers in steering files and details in existing docs or skills.
- **Tool economy:** expensive calls or repeated work that better tooling could reduce.
- **Information access:** missing logs, documentation or read-only service access that would have changed a decision.

Prefer the smallest prevention: remove the mistake through ownership or architecture where practical, then consider types, lint/CI and behavior tests. Use docs for judgment calls. For a proposed check, name the real mistake it should reject and how to verify it does.

Done when each candidate connects evidence to a cause and a specific prevention, including whether an existing mechanism can cover it.

## 3. Discuss

Present candidates in severity order. For each, give the evidence, cause, smallest improvement and expected benefit. Ask for the user's perspective where the evidence leaves intent or tradeoffs unclear.

Finish with recommendations and let the user choose which to implement. Apply improvements only when requested; an earlier explicit request to implement them still applies.

---

Adapted from [Matt Pocock's retro skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/retro/SKILL.md), under the [MIT license](LICENSE).
