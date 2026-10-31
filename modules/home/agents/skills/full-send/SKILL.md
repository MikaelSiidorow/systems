---
name: full-send
description: Take the work end to end to a merged PR. Use when the user says "full send", even as a closing "Full send."
---

# Full send

Do everything in [full-stop](../full-stop/SKILL.md): its grant, steps, proof, gate and asking rules. "full send" adds the permission to merge this PR, so its no-merge rule does not apply; instead of handing off at the gate, merge.

## Merge

- `git fetch`, then re-check the gate on the latest HEAD. If a base commit since the last green run touches the PR's files, `rebase` and run `babysit-pr` again.
- Method: the one the repo's docs name, else the only one the repo allows (`gh api repos/{owner}/{repo}` → `allow_*_merge`), else `--squash`. Admin bypass only where the docs allow it.
- With a merge queue or auto-merge, stay until GitHub reports the PR merged.
- Remove the local worktree and branch.

## Land

Watch every run on the merge commit until it finishes, deploy workflows included (`gh run list -c <sha>`, `gh run watch <id> --exit-status`). If one fails because of this PR, stop and ask before reverting.

## Report

full-stop's report, plus the merge commit and the result of the runs on it.
