---
name: morning-prs
description: Freshen my open PRs in this repo and tell me what to jump on. Use when the user says "morning PRs", "PR status" or "what needs me".
---

# Morning PRs

My open PRs in the current repo, drafts included.

**Freshen** each first, skipping any whose T3 thread is running right now (find it by PR URL or branch); an agent is mid-work there. Behind with no conflicts: `gh pr update-branch --rebase`. Conflicting: `rebase` in a separate worktree.

**Group**, judging checks and reviews on the current HEAD:

1. **Ready to merge**: approved, green, up to date.
2. **Agent can handle**: failing checks, bot comments, human comments with a clear fix. Say what the agent would do.
3. **Needs you**: design questions, feedback you would push back on, drafts that look done, conflicts you could not settle.
4. **Waiting on review**: who has it and since when; past a working day, suggest a nudge without sending it.

**Dispatch** for group 2: propose one per PR and wait for the user's go. Send it to the PR's linked T3 thread (`t3_thread_send`: run `address-review`), else `delegate_task` with `isolation: "worktree"` on the PR's branch.

Report the groups in order, one line per PR with its link, plus what you rebased or skipped.
