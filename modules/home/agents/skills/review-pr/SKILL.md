---
name: review-pr
description: Review someone else's PR for me: is it safe to merge, does it do what it claims, what needs my eyes. Use when the user says "review this PR" or "review #123".
---

# Review PR

Prepare the user's review; the decision stays theirs. Never submit, approve or request changes.

Run one Codex and one Claude review as input and grade their findings yourself (**blocker** / **should** / **nit**). Grade what bots and other reviewers already said instead of repeating it. Skip style.

## Judge, in this order

1. **Safe to merge**: what breaks if it is wrong and who it hits (data, auth, money, public API, infra, migrations, permissions, secrets).
2. **Reversible**: plain revert, revert plus cleanup (migrations, backfills, sent messages, published artifacts), or one-way. The less reversible, the higher the bar.
3. **Does what it claims**: description and ticket against the diff. Do the tests fail without the change, or only exercise mocks?
4. **Scope**: unrelated changes, drive-by refactors, new dependencies, helpers that duplicate existing ones.
5. **Shape**: a much simpler way, in one line, only if there is one.

## Proof

Start from what the author says they verified. List the gaps as tests you can run and tests that need a human (UX feel, real devices, production-like data). Run the cheap ones in a separate worktree.

## Draft

A handful of inline comments at most, blockers and shoulds with file:line, each starting with 🤖. Post them as a **pending** review: `gh api repos/{owner}/{repo}/pulls/<n>/reviews` with `commit_id` (head SHA) and `comments`, but no `body` and no `event`. If the user already has a pending review there, keep the comments in chat.

## Report in chat

Recommendation (approve / approve with comments / request changes) and why; risk and reversibility in a line each; claims verified or not, with what you ran; **needs your eyes** (product or UX calls, domain knowledge, anything unverified) or "skim is enough"; unrelated changes; the inline comments; anything worth testing by hand.
