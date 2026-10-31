---
name: file-ticket
description: File a Linear or GitHub ticket in the right team, project and queue. Use when the user says "file a ticket", "make an issue" or "track this".
---

# File ticket

**Tracker**: the related ticket's (a key like `ENG-123` means Linear, `#123` means GitHub), else ticket keys in the branch name or recent commits, else whether the repo's GitHub issues are in use. Ask only if that leaves it open.

**Duplicates**: search open tickets first. If one matches, link it and offer a comment instead.

**Placement**, where most of the judgement goes:

- **Team**: the related ticket's team, else the team whose recent tickets cover this repo or area. Ask if still unclear; a ticket on the wrong team gets lost.
- **Project**: only when it clearly belongs (a follow-up in that project, or one the user named). Otherwise none.
- **State**: if the team has a Triage state and the ticket is not the user's to start now, file it there and leave priority to the team. If it is the user's to start now: Todo, assigned to them.
- **Labels and priority**: only when clear, and only labels the tracker already has.

**Body**: the problem first (what happens, what should happen), then repro steps or evidence, then acceptance criteria. No implementation plan unless asked. Link the source (PR, thread, error). Run it through `unslop`, and leave out secrets.

Show the draft with team, project and state in its first line, and file it after the user confirms. Report the link.
