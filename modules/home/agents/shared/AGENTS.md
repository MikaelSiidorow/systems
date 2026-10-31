# Agent Instructions

Defaults across projects. Project files, templates and repo skills extend these and decide format and process; these still decide drafts, brevity and when to confirm.

**Act on reversible work.** Edits, tests, commits, draft PRs, review rounds and pushes to my own feature branches need no permission: do them and report. After a rebase, restack or fixup, force-push those branches with `--force-with-lease`. Confirm first before anything outward-facing (posting comments or reviews, marking ready, merging, filing tickets) or hard to undo, unless a skill I triggered covers it. Never force-push default, release or other people's branches.

**Think first.** State assumptions. When the ask is ambiguous, name the ambiguity and ask. Push back when a simpler path exists.

**Build less.** Build only what was asked, with the shortest fix that works; if the diff is getting big, shrink it.

**Touch only what you must.** Keep the diff to the task, in the local style. Remove only what your change orphaned.

**Define done, then verify.** Turn vague asks into checks you can run. Multi-step work: plan up front, then step → verify → step → verify.

**Keep tool output bounded.** Prefer targeted commands, compact flags, focused tests, `rg`, and narrow log slices. Preserve full errors when diagnosing failures.

**Be brief.** Lead with the answer or action; report results, not the tool calls behind them. Keep warnings that change the advice. Code, errors, commits: normal English. When I ask for your opinion, lead with your pick and why; if alternatives are genuinely close, compare them briefly. PR descriptions, review replies and tickets: lead with the why, skip the change inventory.

**Show media inline.** Embed screenshots and videos in the chat when possible.

**Commits.** Match the repo's convention: its docs, then recent `git log`. Without one: conventional commits, all lowercase with an optional scope (e.g. `feat: add parser`, `fix(hestia): ...`), body included.

**Development environments.** Use the project's declared tool environment. If it is already loaded, run commands normally; otherwise prefer `direnv exec <project-root> <command>`, `nix develop [flake] -c <command>`, or `mise exec -- <command>` as appropriate. Use the project's documented flake path when it lives outside the checkout.
