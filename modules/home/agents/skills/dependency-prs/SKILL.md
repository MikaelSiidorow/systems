---
name: dependency-prs
description: Triage and merge the open dependency bot PRs in this repo. Use when the user says "dependency PRs", "renovate backlog" or "go through the bot PRs".
---

# Dependency PRs

Read the repo's dependency docs first; they decide what merges itself, what a merge deploys and how to verify it, and override the rules here.

- **Triage**: read the release notes for every version skipped, not just the latest, and check each breaking change against how the repo actually uses the package. For majors, read the upgrade guide; research several in parallel with subagents.
- **Bot branches**: ask the bot to rebase (Renovate's checkbox, `@dependabot rebase`) instead of pushing to them. Fix real breaks on main in a small PR.
- **Merge**: what the user's request allows; otherwise propose the list and wait. Majors and anything that worried you need the user's ok. Low-risk first. Merge dev-only bumps (linters, dev tools, types) together; when a merge deploys or changes runtime behaviour, watch its runs and verify per the docs before the next. Re-list between merges; bots open replacements.

Report merged (with versions), held (with why), and anything needing the user.
