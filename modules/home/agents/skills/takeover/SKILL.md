---
name: takeover
description: Take over a PR, branch or agent thread and finish its goal. Use when the user says "take over" or "takeover".
---

# Takeover

Finish the original goal and keep the original contributors' credit. The existing implementation is context, not proof: rework it where it is wrong.

## 1. Inherit

Read the source PR, branch or thread: description, commits, review findings, CI and the user's later corrections (`t3_thread_read` for a T3 thread). Resolve it to the actual code at its current head, including uncommitted work in its worktree. Restate the goal in two lines.

## 2. Where the work goes

- **My own PR or branch**: continue in place.
- **Someone else's PR**: a new branch that starts from its commits, with your fixes as separate commits on top, filed as a new draft PR. Push to their branch only when the user says "in place".

Never change, close or merge the original PR without the user's say.

## 3. Finish

- Run `modernize` if the base has moved on, then do what the goal still needs: fix review findings, rework what is wrong, simplify without dropping intended behaviour. Leave unrelated features out.
- Verify the original failure and the real workflow yourself; mocked tests do not prove it. Say what stays unverified.
- Recheck the source before filing: it may have moved while you worked.

## 4. Credit

Keep git authorship and existing `Co-authored-by` trailers. Credit and link the original PR in the description. If the PR will be squashed, keep the human authors as `Co-authored-by` in the squash message, using identities from their commits, not guessed emails.

## 5. Hand off

Use `file-pr`, then `babysit-pr`, or `full-stop`/`full-send` if the user said so. Report what you inherited, what you changed, how you verified it, how credit is kept, and any decision left.
