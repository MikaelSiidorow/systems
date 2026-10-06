---
name: babysit
description: Babysit a local branch or draft PR with Codex and Claude reviews, fixes, security review, and CI monitoring until clean or the review budget is exhausted.
---

# Babysit

Coordinate the work in the main chat. Make routine decisions and fixes autonomously; involve the user only for a genuine blocker.

## Prepare

- Use local mode when requested or when no PR is attached; otherwise use the attached PR, including drafts. Respect review-only requests.
- Commit task-related uncommitted changes before reviewing. Preserve work explicitly meant to remain uncommitted or unstaged, and unrelated work. Leave it in place if it cannot affect the review or checks; otherwise stash only that work and restore its original staged/unstaged state afterward.
- Review committed changes against the requested base, otherwise the actual PR base, otherwise freshly fetched `origin/main` (local `main` fallback). Record the base and HEAD so all reviewers inspect the same candidate.

## Review and fix

- Run independent Codex and Claude code reviews using their built-in review skills or commands, with subagents or CLI processes as appropriate. Reviewers review; the coordinator applies fixes.
- Verify findings, fix real issues, run relevant checks, and commit fixes before reviewing again. Choose amend, fixup/autosquash, or new commits as appropriate. Preserve other authors' work; rewrite published history only when authorized, using force-with-lease.
- Stop early when clean. Allow at most **three regular review-and-fix rounds**, including fixes prompted by CI or Bugbot. Waiting consumes no rounds. If the last round produces fixes, report that they have not been re-reviewed.
- Run **one Claude security review** of the final candidate. If it finds real issues, fix and commit them, then run **one focused confirmation**. Use any remaining regular rounds for code affected by security fixes.
- Ensure draft and repeat reviews actually run. Report unavailable, failed, or skipped reviewers instead of treating them as clean.

## PR checks

- In PR mode, push task fixes and use `gh pr checks --watch` and `gh run view --log-failed` to track CI. Inspect Bugbot findings and relevant review comments as well.
- After each push, verify checks and reviews belong to the current HEAD. Keep monitoring until applicable checks are green and real findings are resolved; neutral or skipped reviews alone do not prove clean.
- Fix real CI/Bugbot findings within the same three-round budget. Stop with an honest incomplete result when that budget cannot cover further work, a genuine blocker remains, or monitoring exceeds 30 minutes unless the user sets another deadline.
- Local mode stays local. Leave PRs unmerged and drafts as drafts.

## Finish

Restore any preserved work. Briefly report final HEAD, review rounds, security passes, fixes, check results, and unresolved or unreviewed changes. Distinguish clean locally from green on the PR.
