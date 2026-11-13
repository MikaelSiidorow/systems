---
name: file-pr
description: Open a draft PR in the repo's format. Use when the user asks to file, open or create a PR.
---

# File PR

Check whether the branch already has a PR; if so, update it instead. Review the diff against the base to make sure it matches the goal.

Format comes from the repo first: a repo PR skill, then its PR template (tick only what you verified), then PR guidance in its docs, then recent merged PRs. These decide structure and section names; a section that needs only a line or `N/A` gets just that. On length, the tighter limit wins: the repo's or the budget below.

Titles usually become commit messages, so follow the repo's convention. Say why the change matters:

> ❌ perf(server): negotiate permessage-deflate on the websocket
>
> ✅ perf(server): cut websocket frame size by 70%+ with gzipping

Open the description with the problem, from the user's original ask, then the fix in a sentence or two. Link the ticket if one is named. Skip the implementation inventory:

> ❌ Removed implicit workspace carry-over from every "new thread" entry point (cmd+n, sidebar buttons, command palette). Deleted buildContextualThreadOptions and the seed-context machinery.
>
> ✅ My "new worktree" default was ignored when starting threads on existing worktrees. Now the preference always applies.

**First screen.** A reader who skips every `<details>` block should know what changed, why, and how we know it works. Aim for 150 words of prose in the whole description outside `<details>`, 250 at most, whatever the PR size; code blocks, tables, images and template boilerplate don't count. When prose can't show the shape (several modules, a changed flow), add one view: a file or call tree, a Mermaid diagram, a diff sketch. Detail only some reviewers need goes in one `<details>` block; the diff carries the inventory.

**Proof.** What you observed, before → after: commands and their results, numbers, screenshots or a recording for UI. Give each result in a line or two; full output goes in `<details>`. With no before to show (docs, a new tool), give what you checked and its limits. "Tests pass" alone is a claim, not proof. Name a test only when it's new and fails without the change. List what you couldn't check as `- [ ]` items, with who checks it. Proof goes in the template's verification or test plan section, else under a closing `## Proof`.

**Risk.** One line: a two-way door or a one-way door, and the blast radius: "Two-way door; blast radius: the settings page." A one-way door leaves something a revert can't undo, such as a migration or backfill, deleted data, sent emails, a removed public API field, issued tokens, or stored data older code reads differently; add a line saying what, and how to recover if you can. Call it two-way only when a revert leaves nothing behind. Risk goes in the template's risk section, else a closing `Risk:` line.

Run the title and body through `unslop`, count the prose outside `<details>` (`wc -w`) and cut to the budget, then check them for secrets and private details.

Open it as a draft: `gh pr create --draft`. If GraphQL is rate-limited, use `gh api repos/<owner>/<repo>/pulls -f title=… -f head=… -f base=… -F draft=true -F body=@<file>`. Report the URL and any template section only the user can fill.

---

Adapted from Theo Browne's PR skill, with the door and blast-radius call and the before → after proof from [Matt Pocock's pr skill](https://github.com/mattpocock/skills/blob/main/skills/engineering/pr/SKILL.md), both under the [MIT license](LICENSE).
