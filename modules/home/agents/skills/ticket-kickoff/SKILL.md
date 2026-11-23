---
name: ticket-kickoff
description: 'Start or plan work from a Linear or GitHub ticket. Use when the user or a delegated brief says to work on or plan a ticket: ENG-123, #45 or a ticket link.'
---

# Ticket kickoff

The reference names the tracker: `ENG-123` or a linear.app link is Linear (MCP); `#123` or a github.com link is a GitHub issue (`gh`).

1. **Read all of it**: description, comments, parent, linked issues and PRs, and attached screenshots (Linear's `extract_images`). Comments often change the ask.
2. **Restate** the goal and acceptance criteria in two lines. Name any ambiguity that changes the result and ask before writing code; decide the reversible rest and list each call in the PR.
3. **Slice.** Estimate the diff. Past about 500 changed lines, look for a stack of tracer bullets: vertical slices a reviewer can read and demo alone, with any prefactoring first; keep a cohesive change together. A wide mechanical change goes expand–contract (add the new form, migrate callers in batches, remove the old), so every PR stays green. Show the numbered stack with each slice's rough size and wait for the user's OK; a delegate proposing a stack returns it to its parent and stops, and one handed an approved slice builds it. A change that fits one readable PR stays one PR. A plan-only ask ends here, with the plan.
4. **Claim it**: assign the ticket to the user and move it to In Progress.
5. **Branch** with the tracker's name, so the PR links back: Linear's `gitBranchName`, or `<number>-<slug>` for a GitHub issue. Each later slice adds a suffix and branches from, and targets, the slice before it. Reference the ticket in each PR; only the last slice closes it (`Closes #123`, or the Linear key).
6. **Work**, one slice per PR, handing over to `full-stop` or `full-send` if the user said so.
