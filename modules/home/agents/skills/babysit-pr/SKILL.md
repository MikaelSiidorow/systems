---
name: babysit-pr
description: Watch my PR through review bots and CI, fixing until green. Use when the user says "babysit" or "watch the PR".
---

# Babysit PR

Own the PR until it is green. Make routine calls yourself; bring the user only a genuine blocker. Merging and marking ready belong to `full-stop` and `full-send`.

## 1. Prepare

- Use the attached PR or the current branch's PR, drafts included. With no PR yet, file one with `file-pr` first.
- If the PR is behind or conflicts with its base, run `rebase` first so review runs on the final base.
- Run `review-rounds` on the branch unless the user or a calling skill skipped it, or it already ran on this HEAD. Push its fixes.

## 2. Watch

One watcher per PR, picked by your tools:

- **`watch_pull_request` is in your tool list** (T3 Code; it may be deferred, so load it first): handle the current checks and comments with `address-review`, call `watch_pull_request`, and end the turn with no message. The watch is your only wait. It wakes you when a check fails, required checks pass, someone comments or reviews, or the branch conflicts, so a rerun or a single workflow is waited on the same way: end the turn.
- **No `watch_pull_request`**: `gh pr checks --watch` waits for checks only. Once it returns, poll `gh pr view --json reviews,comments,mergeStateStatus` every 2 minutes until the expected review bots have posted on the current HEAD. Stop with an honest status after 30 minutes unless the user set another deadline.

Only the thread that owns the PR watches it; a delegated child task hands the PR back to its parent instead.

## 3. On each wake

- Confirm checks and reviews belong to the current HEAD; results for an older HEAD do not count.
- Run `address-review` for new feedback and failures.
- If `mergeStateStatus` is `BEHIND` or `DIRTY`, run `rebase`. `watch_pull_request` wakes on conflicts but not on behind, so check it on every wake.
- Fixes prompted by CI or review count against a budget of **3 fix rounds**. Past it, hand back.
- Hand back when the PR is green, you are blocked, or only the user can answer a question or make a call. Otherwise end the turn with no message and keep watching.

Green means: required checks pass on the current HEAD, every review thread is resolved, and the expected review bots have posted. Neutral or skipped results alone do not prove green. Review bots often skip drafts; on a draft, green covers checks and existing threads only.

## 4. Hand back

A watched thread stays in Working, out of the user's inbox, so anything you write while watching goes unseen. Call `unwatch_pull_request` first, unless a calling skill continues, then report: final HEAD, reviewers that ran, fix rounds used, check results, and anything left open or needing the user.
