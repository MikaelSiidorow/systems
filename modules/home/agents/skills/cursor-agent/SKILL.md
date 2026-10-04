---
name: cursor-agent
description: Delegate a coding or research task to Cursor's cursor-agent CLI as a sub-agent, and list, resume, or cancel those runs. Use when the user asks to hand work to cursor-agent, run a task in the background with cursor-agent, or continue a previous cursor-agent session.
---

# cursor-agent sub-agent

Run `cursor-agent` headless as a sub-agent via the bundled runner. It tracks
each run so you can list, resume, and cancel them.

Runner (stable install path):

```
bash ~/.claude/skills/cursor-agent/cursor-subagent.sh <subcommand> ...
```

## Subcommands

- `run [--name N] --model M [--write] [--worktree] -- <prompt>`
  Start a new sub-agent. Always pass `--model` (see Model selection). Read-only
  planning mode by default; pass `--write` to allow edits and shell (adds
  `cursor-agent --force`). `--worktree` runs in an isolated git worktree named
  after the tracked run.
  Prints the sub-agent's output and its `chatId`.
- `resume <name|chatId> [--model M] -- <prompt>` Continue a tracked run (or a
  raw chatId). Reuses the tracked model by default; only pass `--model` to
  change it (see Model selection).
- `list` Show tracked runs (status, name, mode, model, chatId, started). Check
  MODEL before resume/switch decisions.
- `cancel <name>` Kill a still-running run.

## Sandbox

Every run is sandboxed (`cursor-agent --sandbox enabled`): the agent's shell
commands are confined to the current directory for writes and denied network by
default. There is no opt-out. Note the agent can still *read* files inside the
workspace, including a `.env` — agent mode has no read-blocklist. Don't launch a
run from a directory holding secrets you don't want the sub-agent to read.

## Model selection

Always pass `--model` on `run`. Pick by task difficulty:

- `cursor-grok-4.5-high` (default) — harder work: multi-file changes, debugging,
  design trade-offs, ambiguous requirements, research that needs judgment.
- `composer-2.5` — easier work: small edits, renames, boilerplate, narrow
  lookups, mechanical follow-ups with a clear recipe.

If unsure, use `cursor-grok-4.5-high`. Honor an explicit model from the user.

Keep the same model across a session when possible — switching busts the prompt
cache. `resume` reuses the tracked model automatically.

When the follow-up needs a different model:

- Prefer a fresh `run` (new context) over mid-session switches in most cases.
- Avoid upgrading `composer-2.5` → `cursor-grok-4.5-high` in an existing
  session unless truly necessary; start a new agent instead.
- Downgrading `cursor-grok-4.5-high` → `composer-2.5` is allowed (cheaper), but
  a fresh `run` is often still better than continuing on a colder cache.

## Rules

- Runs block until `cursor-agent` finishes. To run one in the background, invoke
  the runner as a backgrounded Bash job rather than adding any flag.
- Default to read-only. Only pass `--write` when the user clearly wants edits.
- Name runs (`--name`) when the user may want to resume them; otherwise a
  timestamped name is generated.
- To continue a run, prefer `resume <name>` over starting a fresh one.
- Present the sub-agent's output as-is; don't silently redo its work yourself.
