# Dependency updates

Renovate and the flake-lock workflows open the PRs. Merging deploys, so merge one PR at a time and verify before the next. Ask before merging a major, an `infra/**` change or Terraform with a non-empty plan.

## What merges itself

- Workstations and openwrt flake locks.
- The weekly infra flake lock, unless its k8s-server closure brings a new k3s or kernel minor, or a PostgreSQL or systemd major (`deploy.yml` enables auto-merge). Hestia still needs a manual deploy, and a kernel bump a reboot.
- The weekly GitHub Actions group (minor/patch/digest; majors get their own grouped PR for review), but only when it doesn't touch `deploy.yml` or `k8s-rollout.yml`. A shared action like `actions/checkout` pulls those in, so expect to review it most weeks.
- `k8s/**` minor/patch chart and image updates (not 0.x), three days after release, except the monitoring stack (alloy, kube-prometheus-stack, loki, tempo). A release without a publish date (images outside Docker Hub) never gets a PR; force it from the Dependency Dashboard.
- Bot Terraform PRs whose plan shows no changes (`deploy.yml` enables auto-merge).

Everything else waits for review: majors, the monitoring stack, other `infra/**` changes (NixOS, k3s HelmCharts), Terraform with a non-empty plan, the T3 Code pins.

## What a merge deploys

- `k8s/**`: Argo CD syncs it; there is no workflow run, so wait for the app to reach the new revision.
- `infra/**`: `nixos-rebuild switch` on k8s-server through `deploy.yml`. Hestia is never deployed by CI; tell the user to deploy it.
- `terraform/*`, `terraform/k8s/*`: `terraform apply`. Read the plan in the PR's CI report comment.
- `openwrt/**`: builds only; router deploys are manual.

`deploy.yml` runs on pushes touching `infra/nixos/**`, `infra/flake.*`, `terraform/**`, `.sops.yaml`, `deploy.yml` itself or `.github/scripts/reconcile-wger.sh`, so an Actions bump to `deploy.yml` redeploys NixOS. NixOS deploys queue on a lock on k8s-server and deploy `main` as it is, so a run can include later merges.

## Known failures

- openwrt `hash mismatch ... base-packages.adb`: OpenWrt republished its index; the daily lock update fixes it. Leave it.
- Conflicts with main, or CI needs a rerun against it: tick the `rebase-check` box in the PR body and run `gh workflow run renovate.yml`. Don't push to Renovate branches.
- A provider or chart changed its output: fix on main in a separate small PR, then rebase the Renovate PR.

For chart majors, read the chart's upgrade notes (README "Upgrading" or UPGRADE.md) and `helm template` it with our values where it renders.

## Merge order

Low-risk first, then `infra/` flake bumps, then majors one at a time, the ingress (traefik) last. Merge with `--squash`.

## Verify after each merge (`ssh root@89.167.124.71`)

- Argo CD: every app `Synced`/`Healthy` and at the new revision (`kubectl -n argocd get app`). `brawl-draft` being `Progressing` is a known, older state.
- Pods: nothing outside `Running`/`Completed`; note new restarts. A k3s upgrade restarts the DNS, so pods that resolve a DB on startup restart once.
- Memory: for each upgraded container, compare `container_memory_working_set_bytes` with its limit, and check `anon` vs `file` in the cgroup's `memory.stat`. A container with almost no `file` left sits at its limit and thrashes; raise the limit in a follow-up PR with the numbers.
- k3s HelmCharts (argocd, traefik, cert-manager): `kubectl -n kube-system get helmchart <name>` and the `helm-install-<name>` job logs. The Argo CD chart is named `argocd`.
- Ingress changes: `curl` each Ingress host over https and http (expect the same codes as before, http → 301).
- Monitoring changes: Prometheus targets up, rule groups loaded, Alertmanager config still has the Telegram receiver.

Follow-ups for the user: Hestia deploys, reboots for a new kernel, upgrades that need their decision.
