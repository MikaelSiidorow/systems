# Systems

Configuration for my machines, servers and the services on them.

- [`workstations/`](workstations/): nix-darwin work Mac and Pop!_OS home-manager, rebuilt by hand ([README](workstations/README.md))
- [`infra/`](infra/), [`k8s/`](k8s/), [`terraform/`](terraform/): servers, routers and cloud resources, deployed by CI (below)

Each flake has its own `flake.lock`.

## Architecture

```
NixOS (k3s.nix)                              Terraform (terraform/k8s/)
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

- **Terraform** (`terraform/`) provisions cloud infrastructure (Hetzner server, Cloudflare DNS)
- **NixOS** (`infra/nixos/`) manages the Hetzner cluster host and the Hestia home server
- **OpenWrt** (`openwrt/`, own flake and lock) manages the Cerberus router and Hermes access point
- **Terraform K8s** (`terraform/k8s/`) manages application secrets (the part that can't be in Git)
- **ArgoCD** syncs application manifests from `k8s/` in Git to the cluster

## Structure

```
systems/
├── terraform/               # Cloud resources (Hetzner, Cloudflare)
│   └── k8s/                 # K8s secrets (Terraform + kubernetes provider)
├── workstations/            # nix-darwin + home-manager flake (own flake.lock)
├── modules/home/            # Shared home-manager modules: core (shell, CLI tools), agents
├── openwrt/                 # Router firmware + UCI config flake (own flake.lock, updated daily)
├── infra/                   # NixOS flake: Hestia, k8s-server (own flake.lock)
│   ├── nixos/hosts/
│   │   ├── k8s-server/      # Hetzner K3s and public infrastructure
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

## Deploying

Push to `main` triggers deploys automatically based on changed paths. Manual deploys via workflow dispatch (select component: `terraform`, `nixos`, `k8s-terraform`, or `all`).

### Deploy pipeline ordering

```
terraform  →  nixos  →  k8s-terraform
(infra)       (OS)      (app secrets)
                           ↓
                     ArgoCD auto-syncs
                     (app manifests from git)
```

1. **`terraform`** — creates/updates cloud resources (server, DNS)
2. **`nixos`** — deploys NixOS config via deploy-rs (installs K3s, ArgoCD, etc.)
3. **`k8s-terraform`** — creates namespaces and secrets via SSH tunnel to K3s API
4. **ArgoCD** — automatically syncs `k8s/apps/` → application workloads (no CI needed)

K8s manifest changes (`k8s/refinery/`, `k8s/wger/`) are deployed by ArgoCD within ~3 minutes of pushing to `main`. No CI job is needed for these.

Hestia is deployed independently from a machine that can resolve and reach
`hestia.home.arpa`. Deployment uses the normal user and prompts for sudo:

```bash
nix run ./infra#deploy -- ./infra#hestia
```

The existing CI NixOS job continues to deploy only `k8s-server`; Hestia being
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

1. Provision server with Terraform:

   ```bash
   cd terraform && terraform apply
   terraform output k3s_ipv4_address
   ```

2. Update `infra/flake.nix` with the new IP.

3. Install NixOS via nixos-anywhere:

   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake ./infra#k8s-server --target-host root@<IP>
   ```

4. Wait for ArgoCD to start:

   ```bash
   ssh root@<IP> "kubectl get pods -n argocd"
   ```

5. Apply K8s secrets via Terraform:

   ```bash
   cd terraform/k8s
   terraform init
   terraform apply
   ```

6. Verify ArgoCD synced the apps:
   ```bash
   ssh root@<IP> "kubectl get applications -n argocd"
   ```

### Local kubectl access

The K3s API (port 6443) is not exposed to the internet. Use an SSH tunnel:

```bash
ssh -L 6443:127.0.0.1:6443 root@$(terraform -chdir=terraform output -raw k3s_ipv4_address)
```

Then in another terminal:

```bash
# Fetch kubeconfig (one-time)
ssh root@<IP> cat /etc/rancher/k3s/k3s.yaml > ~/.kube/k3s-config

# Use it
KUBECONFIG=~/.kube/k3s-config kubectl get pods -n refinery
```

## Secrets

- **GitHub Actions secrets**: provider tokens (`HCLOUD_TOKEN`, `CLOUDFLARE_API_TOKEN`), SSH keys, R2 credentials, app secrets (`REFINERY_*`)
- **GitHub Actions variables**: `K3S_HOST`
- **K8s secrets**: managed by `terraform/k8s/`, passed as `TF_VAR_*` env vars in CI. `k8s/**/secrets.yaml` is gitignored.
