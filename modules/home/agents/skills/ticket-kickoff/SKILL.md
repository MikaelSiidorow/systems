---
name: ticket-kickoff
description: 'Start or plan work from a Linear or GitHub ticket. Use when the user or a delegated brief says to work on or plan a ticket: ENG-123, #45 or a ticket link.'
---

# Ticket kickoff

The reference names the tracker: `ENG-123` or a linear.app link is Linear (MCP); `#123` or a github.com link is a GitHub issue (`gh`).

1. **Read all of it**: description, comments, parent, linked issues and PRs, and attached screenshots (Linear's `extract_images`). Comments often change the ask.
2. **Restate** the goal and acceptance criteria in two lines. Name any ambiguity that changes the result and ask before writing code; decide the reversible rest and report each call.
3. **Slice.** Estimate the diff. A change that fits one readable PR stays one PR. Past about 500 changed lines, look for a stack of tracer bullets: vertical slices a reviewer can read and demo alone, with any prefactoring first; keep a cohesive change together. A wide mechanical change goes expand–contract (add the new form, migrate callers in batches, remove the old), so every PR stays green. List the numbered stack with each slice's rough size.
   - A plan-only ask ends here, with the plan.
   - Otherwise get the user's OK on the stack through the harness's question tool.
   - A delegate returns a proposed stack to its parent and stops; one handed an approved slice and its base builds only that slice, and the parent keeps the claim, readiness and merging.
4. **Claim it**: assign the ticket to the user and move it to In Progress.
5. **Branch** with the tracker's name, so the PR links back: Linear's `gitBranchName`, or `<number>-<slug>` for a GitHub issue. Slice *n* of a stack is `<branch>-<n>`, branched from slice *n−1* and filed against it as its base. Earlier slices only reference the ticket (`Part of ENG-123`, `Refs #123`); the last one closes it.
6. **Work** slice by slice, handing each to `full-stop` or `full-send` if the user said so. Land a stack bottom-up: once a slice merges, `rebase` the next onto the default branch, retarget it, and run its gate again before it merges.
