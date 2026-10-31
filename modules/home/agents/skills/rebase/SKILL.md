---
name: rebase
description: Rebase my branch or PR onto its fresh base and resolve the conflicts. Use when the user says "rebase", "update the branch" or "fix the conflicts".
---

# Rebase

Mechanical update of a recent branch: same intent, new base. Rebasing authorizes pushing the branch, not merging, closing or changing its base.

## 1. Start

Fetch the base and the branch. Record the branch's head SHA; the push leases against it. Base is the PR base, else the requested one, else the default branch.

Stacked branch: rebase onto its parent branch. If the parent already merged by squash, `git rebase --onto origin/<base> <old parent tip>` so the parent's commits drop out.

## 2. Conflicts

During a rebase, `--ours` is the base and `--theirs` is the PR commit being replayed.

- **Lockfiles and generated files**: take the base's version (`git checkout --ours`), then regenerate with the repo's command once the rebase finishes.
- **`flake.lock`**: take the base's version, then `nix flake update <inputs>` for the inputs this PR bumped.
- **Repo-specific steps** (re-dating migrations, renumbering, codegen): follow the repo's docs.
- **Source**: keep both sides' intent. When both change the same behaviour in incompatible ways, stop and ask with the two sides in a line each.

## 3. Verify and push

- `git range-diff <old-base>..<old-head> <new-base>..HEAD`: no change of the PR's own went missing, and nothing from the base got reverted.
- Run the covering checks.
- `git push --force-with-lease=<branch>:<recorded SHA>`. If the lease fails, someone pushed: fetch and reassess instead of overwriting.

A PR with no local checkout and no conflicts can use `gh pr update-branch --rebase` instead.

Done when the branch sits on the fresh base, checks pass and the push landed. Report the new HEAD, what each conflict took, and anything regenerated. CI reruns on the new HEAD; watching it is the caller's job.
