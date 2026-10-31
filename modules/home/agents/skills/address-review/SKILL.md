---
name: address-review
description: Fix, reply to and resolve a PR's review comments and failing checks. Use when the user says "address review" or "fix the comments".
---

# Address review

One pass over the current state of a PR, then stop. Waiting for more feedback is `babysit-pr`'s job.

## 1. Collect

- Fetch unresolved review threads (GraphQL `reviewThreads`), review bodies and failing checks.
- Keep only feedback newer than the latest push, plus older threads still unresolved.
- For failing checks, read the failed logs (`gh run view --log-failed`).

If GraphQL is rate-limited, read through the REST endpoints (`gh api repos/<owner>/<repo>/pulls/<n>/comments`, `.../reviews`, `.../check-runs`).

## 2. Grade

Check each item against the source before acting. Sort it into one bucket:

- **real**: a bug, a broken caller or a real CI failure
- **false positive**: the code already handles it; you can cite where
- **out of scope**: valid, but beyond the PR's goal
- **flake**: an infrastructure or timing failure unrelated to the change
- **needs the user**: a design question, or a human reviewer you would decline

## 3. Act

- **real**: smallest fix, prefer deleting or narrowing code. Run the covering checks, commit, push, then reply with what changed and the commit.
- **false positive**: reply with the reason and file:line evidence, then resolve.
- **out of scope**: reply declining in one line, then list it as a follow-up in your report.
- **flake**: rerun once (`gh run rerun --failed`) and say so in the report.
- **needs the user**: draft the reply in chat and wait. Post it only after the user approves.

Bot threads: reply and resolve directly. Human threads: resolve only after a fix or with the reviewer's agreement.

## Comments

Start every comment you post with 🤖, then lead with the outcome ("Fixed in `abc1234`: …", "Keeping this: …"), cite the code, check or reproduction, and keep it to a few lines. Check the reply for secrets before posting. Resolve a thread only after GitHub returns the posted reply.

Done when every collected thread has a fix commit or a posted (or drafted) reply, and every failing check is fixed, rerun, or reported.

## Report

Fixed, replied, resolved, rerun, and waiting-on-user items, one line each, plus follow-ups.
