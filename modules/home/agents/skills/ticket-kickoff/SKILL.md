---
name: ticket-kickoff
description: 'Start work from a Linear or GitHub ticket. Use when the user says "work on ENG-123", "pick up #45" or gives a ticket link to implement.'
---

# Ticket kickoff

The reference names the tracker: `ENG-123` or a linear.app link is Linear (MCP); `#123` or a github.com link is a GitHub issue (`gh`).

1. **Read all of it**: description, comments, linked issues and PRs, and attached screenshots (Linear's `extract_images`). Comments often change the ask.
2. **Restate** the goal and acceptance criteria in two lines. Name any ambiguity that changes the result and ask before writing code; decide the rest and say so.
3. **Claim it**: assign the ticket to the user and move it to In Progress.
4. **Branch** with the tracker's name, so the PR links back: Linear's `gitBranchName`, or `<number>-<slug>` for a GitHub issue. Reference the ticket in the PR (`Closes #123`, or the Linear key).
5. **Work**, handing over to `full-stop` or `full-send` if the user said so.
