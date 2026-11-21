# Deploying

Operational reference: how changes reach each machine, first-time setup, cluster access and secrets.

## Architecture

```
NixOS (k3s.nix)                              OpenTofu (tofu/k8s/)
  |                                             |
  |-- Traefik (ingress)                         |-- refinery namespace
  |-- cert-manager (TLS)                        |-- refinery-secrets
  |-- ArgoCD (GitOps)
  |-- Bootstrap Application
  |
  v
ArgoCD auto-syncs from git
  |
  |-- k8s/apps/refinery.yaml  -->  k8s/refinery/*.yaml
  |-- k8s/apps/wger.yaml      -->  k8s/wger/*.yaml
```

**Separation of concerns:**

- **OpenTofu** (`tofu/`) provisions cloud infrastructure (Hetzner server, Cloudflare DNS)
- **NixOS** (`infra/nixos/`) manages the Hetzner cluster host and the Hestia home server
- **OpenWrt** (`openwrt/`, own flake and lock) manages the Cerberus router and Hermes access point
- **OpenTofu K8s** (`tofu/k8s/`) manages application secrets (the part that can't be in Git)
- **ArgoCD** syncs application manifests from `k8s/` in Git to the cluster

## Structure

```
systems/
├── tofu/                    # Cloud resources (Hetzner, Cloudflare)
│   └── k8s/                 # K8s secrets (OpenTofu + kubernetes provider)
├── workstations/            # nix-darwin + home-manager flake (own flake.lock)
├── modules/home/            # Shared home-manager modules: core (shell, CLI tools), agents
├── openwrt/                 # Router firmware + UCI config flake (own flake.lock, updated daily)
├── infra/                   # NixOS flake: Hestia, Olympus (own flake.lock)
│   ├── nixos/hosts/
│   │   ├── olympus/         # Hetzner K3s and public infrastructure
│   │   └── hestia/          # Home Assistant and home-network services
│   └── secrets/             # SOPS-encrypted host secrets
├── k8s/
│   ├── apps/                # ArgoCD Application manifests
│   ├── refinery/            # Refinery K8s manifests
│   ├── wger/                # wger workout manager manifests
│   ├── headscale/           # Headscale ingress
│   └── argocd-ingress/      # ArgoCD ingress
├── docs/                    # Architecture & observability docs
├── bin/                     # Utility scripts (ssh)
└── .github/workflows/
    ├── ci.yml               # PR entry point; CI Summary is the only required check
    ├── workstations.yml     # Workstation flake checks and builds
    ├── deploy.yml           # Infra checks on PRs, deploys on push to main
    ├── update-flake-lock.yml # Lock update PRs per flake
    ├── renovate.yml         # Renovate (config in renovate.json), as mikael-systems-bot
    └── k8s-rollout.yml      # K8s rollout restart (reusable)
```

## Pipeline

Push to `main` triggers deploys automatically based on changed paths. Manual deploys via workflow dispatch (select component: `tofu`, `nixos`, `k8s-tofu`, or `all`).

### Deploy pipeline ordering

```
tofu  →  nixos  →  k8s-tofu
(infra)  (OS)     (app secrets)
                     ↓
               ArgoCD auto-syncs
               (app manifests from git)
                     ↓
                   smoke
```

1. **`tofu`** — creates/updates cloud resources (server, DNS)
2. **`nixos`** — deploys NixOS config via deploy-rs (installs K3s, ArgoCD, etc.)
3. **`k8s-tofu`** — creates namespaces and secrets via SSH tunnel to K3s API
4. **ArgoCD** — automatically syncs `k8s/apps/` → application workloads (no CI needed)
5. **`smoke`** — waits for ArgoCD to sync the commit and the workloads to roll out, then checks that no container restarts and every Ingress host answers (`.github/scripts/smoke.sh`)

K8s manifest changes (`k8s/refinery/`, `k8s/wger/`) are deployed by ArgoCD within ~3 minutes of pushing to `main`; the deploy workflow runs only the smoke job for these.

Hestia is deployed independently from a machine that can resolve and reach
`hestia.home.arpa`. Deployment uses the normal user and prompts for sudo:

```bash
nix run ./infra#deploy -- ./infra#hestia
```

The existing CI NixOS job continues to deploy only `olympus`; Hestia being
offline does not block Hetzner deployments.

Router firmware and deployment outputs are built on x86_64 Linux. Deployments
run persistently through Hestia so they continue if the router briefly drops
the caller's network connection:

```bash
make build-router-firmware
make deploy-cerberus
make deploy-hermes
```

Refinery application releases do not require per-build image tag commits in this repo. The steady-state `refinery-app` and `refinery-zero` Deployments track the promoted mutable `:production` tag, and database migrations run during `refinery-app` startup.

### Initial setup (new server)

1. Provision server with OpenTofu:

   ```bash
   make tf-init tf-apply
   cd tofu && sops exec-env ../infra/secrets/ci.yaml 'tofu output k3s_ipv4_address'
   ```

2. Update `infra/flake.nix` with the new IP.

3. Install NixOS via nixos-anywhere:

   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake ./infra#olympus --target-host root@<IP>
   ```

4. Wait for ArgoCD to start:

   ```bash
   ssh root@<IP> "kubectl get pods -n argocd"
   ```

5. Apply K8s secrets via OpenTofu:

   ```bash
   cd tofu/k8s
   sops exec-env ../../infra/secrets/ci.yaml 'tofu init && tofu apply'
   ```

6. Verify ArgoCD synced the apps:
   ```bash
   ssh root@<IP> "kubectl get applications -n argocd"
   ```

### Local kubectl access

The K3s API (port 6443) is not exposed to the internet. Use an SSH tunnel:

```bash
ssh -L 6443:127.0.0.1:6443 root@$(sops exec-env infra/secrets/ci.yaml 'tofu -chdir=tofu output -raw k3s_ipv4_address')
```

Then in another terminal (the node is still called `k8s-server`: local-path volumes are pinned to the node name, so k3s keeps it through `--node-name`):

```bash
# Fetch kubeconfig (one-time)
ssh root@<IP> cat /etc/rancher/k3s/k3s.yaml > ~/.kube/k3s-config

# Use it
KUBECONFIG=~/.kube/k3s-config kubectl get pods -n refinery
```

## Secrets

- **`infra/secrets/ci.yaml`** (SOPS): secrets that CI and you both need, one environment variable per key: the OpenTofu state passphrase, the provider tokens (`HCLOUD_TOKEN`, `CLOUDFLARE_API_TOKEN`, `SCW_SECRET_KEY`) and the R2 state credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`). Values must be single-line and free of `%`. Encrypted to your post-quantum age key and to CI's, whose private half is the `SOPS_AGE_KEY` Actions secret. `.github/scripts/ci-secrets.sh` loads it into a job. Edit with `sops infra/secrets/ci.yaml`.
- **GitHub Actions secrets**: `SOPS_AGE_KEY`, SSH keys, the GitHub App, the Headscale auth key, app secrets (`REFINERY_*`, `WGER_*`)
- **GitHub Actions variables**: `K3S_HOST`
- **K8s secrets**: managed by `tofu/k8s/`, passed as `TF_VAR_*` env vars in CI. `k8s/**/secrets.yaml` is gitignored.

## OpenTofu state

Both roots keep their state in the `terraform-state` R2 bucket, encrypted with `TF_VAR_state_passphrase` from `infra/secrets/ci.yaml`. Every `tofu` command that touches state needs it, so run them through SOPS: the `make tf-*` targets do, and anything else goes inside `sops exec-env infra/secrets/ci.yaml '<command>'`. Losing the passphrase loses the state, so it lives only in that file, which your age key (backed up in Bitwarden) decrypts.

A run that dies mid-apply can leave its lock behind, and later runs then wait ten minutes and fail with `Error acquiring the state lock`. Check that no deploy is running, then release it with the lock ID from that error:

```bash
cd tofu   # or tofu/k8s
sops exec-env "$(git rev-parse --show-toplevel)/infra/secrets/ci.yaml" 'tofu force-unlock <lock-id>'
```
