---
name: full-stop
description: Take the work end to end to a green PR ready for review, without merging. Use when the user says "full stop", even as a closing "Full stop."
---

# Full stop

The user is not watching; they read your final message later. Own the work from its current state to a ready, green PR, and decide routine calls yourself.

"full stop" grants, for this task only:

- pushing and `--force-with-lease` on the task's branch, marking the PR ready, requesting the reviewers the repo's docs name;
- the test methods Proof needs (running the app, browser, simulators, screenshots), even where repo docs say to ask first. Rules on *how* to test still apply; harness approval prompts still apply.

Never merge, enable auto-merge, enter a merge queue or push to the default branch. If auto-merge is already on, turn it off and say so.

## Steps

1. **Finish the change** with the smallest change that works. On the default branch, branch first.
2. **Prove it** (see Proof).
3. **Draft PR**: `file-pr` if none exists, with one line in the description saying how you proved it. Handle existing comments with `address-review`.
4. **Review while draft**: `review-rounds`, then push its fixes.
5. **Ready**: `rebase` if behind, `gh pr ready`, request the reviewers the repo's docs name.
6. **Bots and CI**: `babysit-pr` until green, skipping its review rounds. Prove each fix before pushing it.
7. **Gate, then hand off** (see Gate and Report).

Stay active from 1 to 7: ending the turn while something is pending stops the work. In T3, `babysit-pr`'s watch wakes you.

## Proof

Evidence you observed in this session, the most direct the change allows: reproduce the failure, fix, watch the same reproduction pass; run the checks CI runs; add one focused test that fails without the fix when the behaviour has none; for UI or runtime changes, run the app and look, and attach screenshots when they help. Green mocked tests do not prove the user experience. No proof means no confidence: ask.

## Gate

On the latest HEAD: proof covers every change, required checks are green, review bots have finished with each finding fixed or dismissed with a reason, no human review requests changes, and the branch is up to date and mergeable.

## Asking

Ask only when you cannot continue alone: you cannot prove the change, the gate cannot pass and you cannot fix it, the next step is outside the grant (production, deleting data, anything outside the repo, closing or force-pushing another PR), or the goal is ambiguous in a way that changes the result. Decide the rest and list those decisions in the report.

Use the harness's question tool (`AskUserQuestion`, `request_user_input`) with the PR link, the blocker and options, your pick first; a question in a plain message goes unseen. If there is no tool or no answer, take the safe path and lead the final message with the question.

## Report

Call `unwatch_pull_request` first. Then: PR link, final HEAD, verdict (**ready**, **waiting on approval** or **blocked** and why), proof, reviewers and rounds, and the decisions you made.
