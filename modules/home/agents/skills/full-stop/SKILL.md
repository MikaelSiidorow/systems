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
3. **Draft PR**: `file-pr` if none exists; its Proof carries step 2. Handle existing comments with `address-review`.
4. **Review while draft**: `review-rounds`, then push its fixes.
5. **Draft hold**, only when the user asked to keep it a draft, meaning they will read it first: `babysit-pr` until the draft's required checks are green, then hand off the card (see Report) with the verdict **ready for your read** and end the turn. When the user approves that HEAD, continue.
6. **Ready**: `rebase` if behind, `gh pr ready`, request the reviewers the repo's docs name.
7. **Bots and CI**: `babysit-pr` until green, skipping its review rounds. Prove each fix before pushing it.
8. **Gate, then hand off** (see Gate and Report).

Stay active through every step but the draft hold: ending the turn while something is pending stops the work. In T3, `babysit-pr`'s watch wakes you.

## Proof

Evidence you observed in this session, the most direct the change allows: reproduce the failure, fix, watch the same reproduction pass; run the checks CI runs; add one focused test that fails without the fix when the behaviour has none; for UI or runtime changes, run the app and look, and attach screenshots when they help. Green mocked tests do not prove the user experience. No proof means no confidence: ask.

## Gate

On the latest HEAD: proof covers every change, required checks are green, review bots have finished with each finding fixed or dismissed with a reason, no human review requests changes, and the branch is up to date and mergeable.

## Asking

Ask only when you cannot continue alone: you cannot prove the change, the gate cannot pass and you cannot fix it, the next step is outside the grant (production, deleting data, anything outside the repo, closing or force-pushing another PR), or the goal is ambiguous in a way that changes the result. Decide the rest and list those decisions in the report.

Use the harness's question tool (`AskUserQuestion`, `request_user_input`) with the PR link, the blocker and options, your pick first; a question in a plain message goes unseen. If there is no tool or no answer, take the safe path and lead the final message with the question.

## Report

Call `unwatch_pull_request` first. Then hand off with one card that lets the user trust the PR without opening it:

- title, link, final HEAD, and the verdict: **ready for your read**, **ready**, **waiting on approval** or **blocked** and why;
- size (`+/-` lines, files) and the PR's Risk line;
- **Scope**: the ask in one line, and whether the PR does exactly that, naming anything left out or added;
- **Proof**, shown rather than told: the recording or screenshots for UI, before → after output or numbers otherwise. Inline a short code excerpt only when nothing observable can show the change;
- **Review council**: each reviewer, human or bot, and each `review-rounds` model, with its rounds, findings fixed or dismissed, and final verdict;
- the decisions you made, and the open `- [ ]` items the user owns.

In T3, render it with `html_preview` and `html_render`, embedding screenshots and colouring the door call and each reviewer's verdict (green clean, amber open); elsewhere, write it as Markdown.
