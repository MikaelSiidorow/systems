# Systems

Configuration for my machines, servers and the services on them: workstations, coding agents, a small K3s cluster on Hetzner, a home server and the home network. Each flake has its own `flake.lock`.

## Workstations and agents

- [`workstations/`](workstations/README.md): nix-darwin for the work Mac and standalone home-manager for Pop!_OS, rebuilt by hand.
- [`modules/home/core/`](modules/home/core/): shared shell (zsh, direnv, nix-index) and CLI tools.
- [`modules/home/agents/`](modules/home/agents/README.md): Claude Code and Codex setup. It installs the CLIs, my global `AGENTS.md`, settings baselines that merge into the local config, and a set of skills for taking work from a ticket to a merged PR.

## Infrastructure

- [`infra/`](infra/): NixOS flake for the Hetzner K3s host (`k8s-server`) and [Hestia](infra/nixos/hosts/hestia/README.md), the home server running Home Assistant and the Tailscale subnet router. Host secrets are SOPS-encrypted.
- [`k8s/`](k8s/): manifests that ArgoCD syncs from Git: Refinery, [wger](docs/wger.md), Headscale ingress and the [observability stack](docs/observability.md).
- [`terraform/`](terraform/): Hetzner server and Cloudflare DNS; `terraform/k8s/` manages cluster secrets, the part that can't live in Git.
- [`openwrt/`](openwrt/): firmware builds and UCI config for the [Cerberus router](openwrt/r6220/README.md) and the [Hermes access point](openwrt/archer-c6-v2/README.md).

The tailnet and network layout are in [docs/headscale-network-diagram.md](docs/headscale-network-diagram.md).

## Deploying

Pushing to `main` deploys whatever changed: Terraform, then NixOS via deploy-rs, then the K8s secrets. ArgoCD syncs `k8s/` within about 3 minutes and a smoke job checks the rollout. Hestia and the routers are deployed by hand.

- [docs/deploying.md](docs/deploying.md): pipeline order, manual deploys, setting up a new server, kubectl access and secrets.
- [docs/dependencies.md](docs/dependencies.md): Renovate and flake-lock PRs, what merges itself and how to verify each merge.
