# Dependency updates

Renovate and the flake-lock workflows open the PRs. Renovate runs on Mondays, except for the T3 Code pins (`llm-agents`), which it bumps daily; a red T3 Code PR usually means a patch in `modules/t3code/patches.nix` lost its anchor. Merging deploys, so merge one PR at a time and verify before the next. Ask before merging a major, an `infra/**` change or Terraform with a non-empty plan.

## What merges itself

- Workstations and openwrt flake locks.
- The weekly infra flake lock, unless its olympus closure brings a new k3s or kernel minor, or a PostgreSQL or systemd major (`deploy.yml` enables auto-merge). Hestia still needs a manual deploy, and a kernel bump a reboot.
- The weekly GitHub Actions group (minor/patch/digest; majors get their own grouped PR for review), but only when it doesn't touch `deploy.yml` or `k8s-rollout.yml`. A shared action like `actions/checkout` pulls those in, so expect to review it most weeks.
- `k8s/**` minor/patch chart and image updates (not 0.x), three days after release, except the monitoring stack (alloy, kube-prometheus-stack, loki, tempo) and `k8s/infrastructure/` (Traefik, cert-manager). A release without a publish date (images outside Docker Hub) never gets a PR; force it from the Dependency Dashboard.
- Bot Terraform PRs whose plan shows no changes (`deploy.yml` enables auto-merge).

Everything else waits for review: majors, the monitoring stack, `k8s/infrastructure/`, other `infra/**` changes (NixOS, k3s HelmCharts), Terraform with a non-empty plan, the T3 Code pins.

## What a merge deploys

- `k8s/**`: Flux syncs it; the deploy workflow runs only the smoke job, which waits for every Kustomization and HelmRelease to reach the new revision.
- `infra/**`: `deploy.yml` builds olympus's system in CI, copies it over and switches to it. Hestia is never deployed by CI; tell the user to deploy it.
- `tofu/*`: `tofu apply`. Read the plan in the PR's CI report comment.
- `openwrt/**`: builds only; router deploys are manual.

`deploy.yml` runs on pushes touching `infra/nixos/**`, `infra/flake.*`, `tofu/**`, `.sops.yaml`, `k8s/**` (smoke only) or `deploy.yml` itself, so an Actions bump to `deploy.yml` redeploys NixOS. NixOS deploys queue on a lock on olympus. Each deploys the commit that triggered it, and a run that waited behind a newer commit skips if olympus runs it, and fails otherwise.

## Known failures

- openwrt `hash mismatch ... base-packages.adb`: OpenWrt republished its index; the daily lock update fixes it. Leave it.
- Conflicts with main, or CI needs a rerun against it: tick the `rebase-check` box in the PR body and run `gh workflow run renovate.yml`. Don't push to Renovate branches.
- A provider or chart changed its output: fix on main in a separate small PR, then rebase the Renovate PR.

For chart majors, read the chart's upgrade notes (README "Upgrading" or UPGRADE.md) and `helm template` it with our values where it renders.

## Merge order

Low-risk first, then `infra/` flake bumps, then majors one at a time, the ingress (traefik) last. Merge with `--squash`.

## Verify after each merge (`ssh root@89.167.124.71`)

- Flux: every Kustomization and HelmRelease Ready at the new revision (`kubectl -n flux-system get kustomizations,helmreleases`); a failed chart upgrade rolls back and shows in the HelmRelease's events.
- Pods: nothing outside `Running`/`Completed`; note new restarts. A k3s upgrade restarts the DNS, so pods that resolve a DB on startup restart once.
- Memory: for each upgraded container, compare `container_memory_working_set_bytes` with its limit, and check `anon` vs `file` in the cgroup's `memory.stat`. A container with almost no `file` left sits at its limit and thrashes; raise the limit in a follow-up PR with the numbers.
- k3s HelmCharts (flux-operator): `kubectl -n kube-system get helmchart <name>` and the `helm-install-<name>` job logs.
- Ingress changes: `curl` each Ingress host over https and http (expect the same codes as before, http → 301).
- Monitoring changes: Prometheus targets up, rule groups loaded, Alertmanager config still has the Telegram receiver.

Follow-ups for the user: Hestia deploys, reboots for a new kernel, upgrades that need their decision.
