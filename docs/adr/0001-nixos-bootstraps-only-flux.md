# NixOS bootstraps only Flux

- Status: accepted, migrating
- Date: 2026-11-25

## Context

k3s applies every manifest in its manifests directory. olympus used that to
install Traefik, its CRDs, cert-manager and the ClusterIssuers before any
GitOps tool existed, and later Argo CD itself, whose UI needed ingress and TLS
before it could sync anything.

Flux replaced Argo CD and pulls from Git; it needs neither ingress nor TLS to
start. Keeping the controllers in NixOS now costs more than it gives:

- A Traefik or cert-manager bump is a NixOS deploy instead of a Flux sync.
- Helm never upgrades a chart's CRDs, so Traefik's 25 CRDs are committed as a
  generated 9,400-line file, with a script, a CI check and a Renovate
  post-upgrade task to keep it current.
- Renovate, the render script and the dependency docs each carry a special
  case for k3s HelmCharts.
- k3s never deletes what a removed manifest applied, and deleting a HelmChart
  uninstalls its release, so taking anything out of k3s takes a hand-run step.

## Decision

NixOS installs the Flux Operator and the `FluxInstance`, syncs the SOPS age
key into `flux-system`, and nothing else. Flux reconciles the rest in layers:

```
infrastructure-controllers   Traefik, cert-manager (HelmReleases, CRDs)
  └─ infrastructure-configs  ClusterIssuers, the DNS-01 token
       └─ each app's own Kustomization (dependsOn infrastructure-configs)
```

Apps keep a Kustomization each, so one broken app doesn't hold back the
others. There is no separate platform layer: monitoring is an app that
depends on the configs like the rest.

Moving a k3s HelmChart to Flux detaches it first (remove the manifest, strip
the HelmChart's `wrangler.cattle.io/on-helm-chart-remove` finalizer, delete
it), then adopts the live release with a HelmRelease of the same name and
namespace. k3s records ownership in `objectset.rio.cattle.io` annotations, not
ownerReferences, so no garbage collection follows. AddOn objects stay until
deleting one is shown to leave its objects alone.

Flux's HelmReleases skip CRD upgrades by default too, so Traefik's sets
`install.crds` and `upgrade.crds` to `CreateReplace`; that is what retires
the committed CRD file. cert-manager templates its CRDs (`crds.enabled`), so
Helm already upgrades them.

`infrastructure-controllers` health-checks only its HelmReleases rather than
waiting on everything it applies, so a chart repository's index outage
doesn't count as a failure.

Traefik and cert-manager updates wait for review, like the monitoring stack,
until dependency triage is automated.

## Consequences

- One path for every cluster dependency: Flux applies it and Renovate's flux
  manager bumps it.
- A failing controller upgrade, or a config that fails to apply or decrypt,
  holds back every app's syncs until it is fixed or rolled back. Running
  workloads keep running. That is the intended order: apps need ingress and
  TLS.
- A fresh cluster comes up from NixOS plus Git: Flux installs the controllers,
  then their config, then the apps.
- The host-tied Services (headscale, refinery's database) and the app repos'
  `ci-deploy` RBAC can move to `k8s/` the way `k8s/wger/db.yaml` did, leaving
  k3s's manifests directory to the Flux bootstrap.
