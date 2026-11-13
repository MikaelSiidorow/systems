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

**First screen.** A reader who skips every `<details>` block should know what changed, why, and how we know it works. Aim for 150 words in the whole description outside `<details>`, 250 at most, whatever the PR size. A bigger PR adds the smallest view that shows its shape (a before → after table, a file or call tree, a Mermaid diagram, a diff sketch) and puts further detail in `<details>` blocks.

**Proof.** What you observed, before → after: commands and their output, numbers, screenshots or a recording for UI. With no before to show (docs, a new tool), give what you checked and its limits. "Tests pass" alone is a claim, not proof. Name a test only when it's new and fails without the change. List what you couldn't check as unchecked items, with who checks it. Put it in the template's verification or test plan section, else under `## Proof`.

**Risk.** One line: a two-way door (a revert undoes it) or a one-way door, and the blast radius: "Two-way door; blast radius: the settings page." A one-way door leaves something a revert can't undo, such as a migration or backfill, deleted data, sent emails, a removed public API field, issued tokens, or stored data older code reads differently; add a line saying what, and how to recover if you can. Call it two-way only when a revert leaves nothing behind. Put it in the template's risk section, else under a `## Risk` heading.

Run the title and body through `unslop`, then check them for secrets and private details.

Open it as a draft: `gh pr create --draft`. If GraphQL is rate-limited, use `gh api repos/<owner>/<repo>/pulls -f title=… -f head=… -f base=… -F draft=true -F body=@<file>`. Report the URL and any template section only the user can fill.

---

Adapted from Theo Browne's PR skill, with the door and blast-radius call and the before → after proof from [Matt Pocock's pr skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/pr/SKILL.md), both under the [MIT license](LICENSE).
