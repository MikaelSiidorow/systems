# Agent notes

- Dependency PRs (Renovate, flake locks): read [docs/dependencies.md](docs/dependencies.md) first. It says what merges itself, what each merge deploys and how to verify it.
- Deploys, server setup, cluster access and secrets: [docs/deploying.md](docs/deploying.md).
- Architecture decisions and why: [docs/adr/](docs/adr/). Read the relevant one before changing what it covers; record a new decision as the next numbered file.
- Adding or removing a skill, host, app or router: update the README that lists it in the same change (the root README, or [modules/home/agents/README.md](modules/home/agents/README.md) for skills).
