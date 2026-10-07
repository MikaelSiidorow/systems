---
name: renovate-backlog
description: Work through the open Renovate and flake-lock PRs in this repo, check changelogs, merge them one at a time and verify each deploy on k8s-server. Use when asked to go through, triage or merge the dependency PR backlog.
---

# Renovate backlog

Merging deploys, so merge one PR at a time and verify before the next. Report anything scary instead of merging it.

## What merges itself

- Workstations and openwrt flake locks, GitHub Actions minor/patch (except `deploy.yml` and `k8s-rollout.yml`).
- `k8s/**` minor/patch chart and image updates (not 0.x).
- Bot Terraform PRs whose plan shows no changes (`deploy.yml` enables auto-merge).
- Everything else is left for review: majors, `infra/**` (NixOS, k3s HelmCharts), Terraform with a non-empty plan, the T3 Code pins.

## Triage

1. `gh pr list --state open` with mergeable state and checks. For each PR note what it touches and what merging deploys:
   - `k8s/**`: Argo CD syncs it.
   - `infra/**`: `nixos-rebuild switch` on k8s-server. Hestia is never deployed by CI; tell the user to deploy it.
   - `terraform/*`, `terraform/k8s/*`: `terraform apply`. Read the plan in the PR's CI report comment.
   - `openwrt/**`: builds only; router deploys are manual.
2. Failing checks: read `gh run view --log-failed`. Common causes:
   - openwrt `hash mismatch ... base-packages.adb`: OpenWrt republished its index; the daily lock update fixes it. Leave it.
   - Out of date with main: tick the `rebase-check` box in the PR body and run `gh workflow run renovate.yml`. Don't push to Renovate branches yourself.
   - A provider or chart changed its output: fix on main in a separate small PR, then rebase the Renovate PR.
3. Read the release notes for every version skipped, not just the latest. For majors, read the chart's upgrade notes (README "Upgrading" or UPGRADE.md) and check each breaking change against our values. If a chart can be rendered, `helm template` it with our values. Use subagents to research several majors in parallel.

## Merge

Order: low-risk first, then `infra/` flake bumps, then majors one at a time, the ingress (traefik) last.

- `gh pr merge <n> --squash`. Never merge two `infra/` PRs while a NixOS deploy is still running.
- Watch the deploy: `gh run list -w deploy.yml -c <sha>`, then `gh run watch <id> --exit-status`.
- Renovate may open replacement PRs (new majors) while you work; re-list before each merge.

## Verify after each merge (`ssh root@89.167.124.71`)

- Argo CD: every app `Synced`/`Healthy` and at the new revision (`kubectl -n argocd get app`). `brawl-draft` being `Progressing` is a known, older state.
- Pods: nothing outside `Running`/`Completed`; note new restarts. A k3s upgrade restarts the DNS, so pods that resolve a DB on startup restart once.
- Memory: for each upgraded container, compare `container_memory_working_set_bytes` with its limit, and check `anon` vs `file` in the cgroup's `memory.stat`. A container with almost no `file` left sits at its limit and thrashes; raise the limit in a follow-up PR with the numbers.
- k3s HelmCharts (argocd, traefik, cert-manager): `kubectl -n kube-system get helmchart <name>` and the `helm-install-<name>` job logs. The Argo CD chart is named `argocd`.
- Ingress changes: `curl` each Ingress host over https and http (expect the same codes as before, http → 301).
- Monitoring changes: Prometheus targets up, rule groups loaded, Alertmanager config still has the Telegram receiver.

## Report

List what merged with versions, anything you fixed, what's still open and why, and follow-ups for the user (Hestia deploy, reboot for a new kernel, upgrades that need their decision).
