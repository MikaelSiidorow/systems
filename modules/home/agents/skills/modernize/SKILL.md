---
name: modernize
description: Bring an old PR up to date, checking it still belongs before rebasing. Use when the user says "modernize" or asks whether a stale PR is still needed.
---

# Modernize

Modernize the idea, not just the branch: a clean rebase does not prove the PR still belongs. For a recent branch that only needs a new base, use `rebase` instead.

## 1. Intent

Read the PR's title, body, linked ticket, commits, review threads and full diff. State the smallest coherent goal it was after. Record its base, head SHA and merge-base.

## 2. What changed around it

Read what landed on the base since the merge-base, and search merged and open PRs for a replacement or competing change. Look past overlapping lines:

- Is the same problem already solved?
- Did the APIs, types, schemas or boundaries it relies on change?
- Was the code it changes deleted, moved or simplified on purpose?
- Would landing it bring back old behaviour or a second way to do the same thing?
- Is the benefit still worth its maintenance cost?

## 3. Verdict

- **MODERNIZE**: the goal and shape still hold. Run `rebase`, resolving conflicts by the PR's intent and the base's newer invariants.
- **REWORK**: the goal holds but a mechanical rebase keeps the wrong implementation. Describe the smallest credible rewrite and stop, unless the user asked for the rework.
- **CLOSE**: superseded, obsolete or not worth it. Cite the evidence and stop; closing is the user's call.

Age and sunk effort are not evidence either way.

## Report

Lead with the verdict and why, then the base changes that mattered, conflicts or "no conceptual conflicts", the rebase and checks if done, and what remains. Keep facts and judgement apart.
