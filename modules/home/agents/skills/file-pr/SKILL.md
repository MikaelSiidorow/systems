---
name: file-pr
description: Open a draft PR in the repo's format. Use when the user asks to file, open or create a PR.
---

# File PR

Check whether the branch already has a PR; if so, update it instead. Review the diff against the base to make sure it matches the goal.

Format comes from the repo first: a repo PR skill, then its PR template (fill every section, tick only what you verified), then PR guidance in its docs, then recent merged PRs. These decide structure; the rules below still decide drafts and brevity.

Titles usually become commit messages, so follow the repo's convention. Say why the change matters:

> ❌ perf(server): negotiate permessage-deflate on the websocket
>
> ✅ perf(server): cut websocket frame size by 70%+ with gzipping

Open the description with the problem, from the user's original ask, then the fix in a sentence or two. Link the ticket if one is named. Skip the implementation inventory:

> ❌ Removed implicit workspace carry-over from every "new thread" entry point (cmd+n, sidebar buttons, command palette). Deleted buildContextualThreadOptions and the seed-context machinery.
>
> ✅ My "new worktree" default was ignored when starting threads on existing worktrees. Now the preference always applies.

Include concrete verification evidence: the checks run and their results, with before/after output or screenshots when available. Use a small diagram, tree or diff sketch when it makes the change easier to understand.

Assess reversibility and blast radius. Explain material deployment risks, affected consumers and rollback limits in the repo's format; a separate risk section is optional. Scale the detail to the change.

Run the title and body through `unslop`, then check them for secrets and private details.

Open it as a draft: `gh pr create --draft`. If GraphQL is rate-limited, use `gh api repos/<owner>/<repo>/pulls -f title=… -f head=… -f base=… -F draft=true -F body=@<file>`. Report the URL and any template section only the user can fill.
