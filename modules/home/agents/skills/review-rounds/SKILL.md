---
name: review-rounds
description: Codex and Claude review loop on a branch, fixing until clean. Use when the user says "review rounds" or "review this branch".
---

# Review rounds

You are the lead: reviewers review, you grade and fix. Make routine calls yourself; bring the user only a genuine blocker or a stuck dispute.

## 1. Scope

- Commit task-related uncommitted changes. Leave unrelated or deliberately uncommitted work in place when it cannot affect the review; otherwise stash only that work and restore its staged/unstaged state at the end.
- Base: the requested base, else the PR base, else `main`, fetched fresh from `origin`. Review from the merge-base (`git merge-base origin/<base> HEAD`), so a branch that is behind still shows only its own changes. Record the merge-base and HEAD so every reviewer sees the same candidate.
- Write the intent and what is out of scope in one or two sentences. Run the covering checks; note missing or already-failing ones in the brief.

Done when base, HEAD, intent and check results are written down.

## 2. Reviewers

- Each round runs an independent Codex review and an independent Claude review, using their built-in review commands or skills. In T3, start each round with a fresh `delegate_task` (`role: "review"`, new `clientRequestId`), with models picked through `orchestrator_capabilities`.
- From Claude Code, run `codex review` as a standalone command, with no pipes, redirects or `&&`, in the background; otherwise it runs inside Claude's sandbox and cannot start.
- The native commands own their review prompt and output format. Pass what each accepts: `codex review --base <merge-base>` with intent, out of scope and, from round 2, the open ledger ids as its custom instructions; Claude's review command with the PR or branch as its target. When a delegated child runs a review, tell it to stay review-only and return the command's findings unedited.
- Translate every reviewer's findings into the ledger and grade them yourself. **blocker** = the intended case is wrong. **should** = a real bug callers will hit, within the intent. **nit** = everything else, including other paths, rare cases, small perf and extra compatibility. A reviewer approves when its run reports no blocker or should under your grading.
- A timeout, error or missing reply is a failed reviewer, not an approval: rerun it or report it.

## 3. Ledger and fixes

Keep a **ledger**: id, severity (your grade), outcome (`fixed` / `disagree` / `declined`), evidence.

- Re-grade every finding yourself, whatever label it came with.
- Agree: apply the smallest fix. Prefer deleting or narrowing code over adding guards, helpers or options. Add one focused test only when the intent needs it.
- Disagree: record why with file:line, a test or output. Agree only when the evidence convinces you.
- Nits and out-of-scope findings: decline in one line and list them as follow-ups.
- After fixing, rerun the checks and `git diff --shortstat <base>`. If review grew the diff, cut it back. Commit fixes (amend, fixup or new commit as fits); rewrite published history only with `--force-with-lease`.

## 4. Rounds

- Budget: **3 rounds**, or what the user sets. Up to **5** only while a blocker or should stays open on security, auth, data loss or concurrency.
- Every round reviews the current candidate from the same merge-base. Match each new finding to an existing ledger id where it is the same issue; mark an old id `resolved` when no reviewer raises it again and your fix covers it.
- Start another round only while budget remains and a blocker or should is open, or behaviour code changed since the last approval. A round that returns only nits ends the loop.
- Last, run **one Claude security review** of the final candidate. If it finds real issues, fix them and run one focused confirmation.

Done when both reviewers approve the current behaviour diff with no open blocker or should, or the budget runs out (that is not approval). An item disputed twice goes to the user with both sides in two lines each.

## 5. Report

Leave pushing to the caller. Report:

- each reviewer that actually ran, with its model, and any that failed or were skipped
- rounds used, security pass result
- fixed and declined findings with one-line reasons
- diff size before and after
- fixes made after the last review, marked unreviewed

Restore any preserved work.
