# Agents

Home-manager module that installs Claude Code, Codex and (on Linux) OpenCode, and links the config I author here into each tool's home directory. Runtime state (auth, caches, history, local settings) stays out of Nix.

## What gets installed

- [`shared/AGENTS.md`](shared/AGENTS.md): my global instructions, linked to `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.
- [`config.nix`](config.nix): settings baselines merged into `~/.claude/settings.json` and `~/.codex/config.toml` on every switch. Baseline keys win and the rest of each file is kept, so local and work-only settings survive. It also registers each skill and the agents it targets.
- [`codex/rules/`](codex/rules/): Codex command rules, such as pre-approved read-only `gh` calls.
- [`claude-code/statusline-command.sh`](claude-code/statusline-command.sh): the Claude Code status line.
- [`packages.nix`](packages.nix): the CLIs themselves (from the `claude-code-nix`, `codex-cli-nix` and `opencode-nix` flake inputs) and shell aliases such as `c`, `cco` and `crew`.

## Skills

Each skill in [`skills/`](skills/) is installed for both Claude Code and Codex. Most cover my PR workflow end to end, from picking up a ticket to merging.

| Skill | What it does |
| --- | --- |
| [ticket-kickoff](skills/ticket-kickoff/SKILL.md) | Start work from a Linear or GitHub ticket |
| [file-pr](skills/file-pr/SKILL.md) | Open a draft PR in the repo's format |
| [file-ticket](skills/file-ticket/SKILL.md) | File a ticket in the right team, project and queue |
| [review-rounds](skills/review-rounds/SKILL.md) | Codex reviews a branch in a loop, fixing until clean; Claude only on escalation |
| [review-pr](skills/review-pr/SKILL.md) | Review someone else's PR: is it safe to merge, what needs my eyes |
| [address-review](skills/address-review/SKILL.md) | Fix, reply to and resolve review comments and failing checks |
| [babysit-pr](skills/babysit-pr/SKILL.md) | Watch a PR through review bots and CI, fixing until green |
| [full-stop](skills/full-stop/SKILL.md) | Take work to a green PR ready for review |
| [full-send](skills/full-send/SKILL.md) | Take work to a merged PR |
| [takeover](skills/takeover/SKILL.md) | Pick up a PR, branch or agent thread and finish it |
| [rebase](skills/rebase/SKILL.md) | Rebase onto a fresh base and resolve conflicts |
| [modernize](skills/modernize/SKILL.md) | Check an old PR still belongs, then bring it up to date |
| [morning-prs](skills/morning-prs/SKILL.md) | Freshen my open PRs and say what needs me |
| [dependency-prs](skills/dependency-prs/SKILL.md) | Triage and merge dependency bot PRs |
| [grilling](skills/grilling/SKILL.md) | Stress-test a plan or decision |
| [retro](skills/retro/SKILL.md) | Find improvements to the agent setup from a session or review |
| [unslop](skills/unslop/SKILL.md) | Cut AI tells and padding from prose |
| [writing-for-agents](skills/writing-for-agents/SKILL.md) | Guidance for writing skills and AGENTS.md files |

Some skills are adapted from other people's work under MIT: `file-pr`, `full-send`, `full-stop`, `modernize` and `takeover` from Theo Browne; `grilling`, `retro` and `writing-for-agents` from Matt Pocock; `unslop` from Siqi Chen. Each one keeps its `LICENSE`. The rest are mine.

To add a skill, create `skills/<name>/SKILL.md`, register it in the `skills` set in `config.nix`, and add a row above.
