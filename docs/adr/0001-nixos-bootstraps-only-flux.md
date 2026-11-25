# NixOS bootstraps only Flux

- Status: accepted, migrating
- Date: 2026-11-25

## Context

k3s applies every manifest in its manifests directory. Before olympus had a
GitOps tool, NixOS used that directory to install Traefik, Traefik's CRDs,
cert-manager, and the ClusterIssuers. Later it installed Argo CD the same way.
Argo CD's UI needed ingress and TLS before it could sync anything.

Flux has replaced Argo CD. It pulls from Git and does not need ingress or TLS
to start. Keeping the controllers in NixOS adds extra work:

- Upgrading Traefik or cert-manager requires a NixOS deploy instead of a Flux
  sync.
- Helm does not upgrade a chart's CRDs. Traefik's 25 CRDs are checked in as a
  generated 9,400-line file. A script, a CI check, and a Renovate post-upgrade
  task exist just to keep it current.
- Renovate, the render script, and the dependency docs each need a special case
  for k3s HelmCharts.
- k3s leaves applied objects behind when a manifest is removed, and deleting a
  HelmChart uninstalls its release. Moving anything out of k3s takes manual
  steps.

## Decision

NixOS installs only the Flux Operator and the `FluxInstance`, and syncs the
SOPS age key into `flux-system`. Flux reconciles everything else in layers:

```
infrastructure-controllers   Traefik, cert-manager (HelmReleases, CRDs)
  └─ infrastructure-configs  ClusterIssuers, the DNS-01 token
       └─ each app's own Kustomization (dependsOn infrastructure-configs)
```

Each app keeps its own Kustomization so one broken app does not block the
others. There is no separate platform layer. Monitoring is an app that depends
on `infrastructure-configs` like the rest.

To move a k3s HelmChart to Flux, detach it from k3s first, then adopt the live
release with a HelmRelease of the same name and namespace. Remove the manifest
from NixOS, then run these steps by hand in order:

1. Annotate the HelmChart with `helmcharts.helm.cattle.io/unmanaged` so k3s's
   helm-controller ignores it. Without this annotation, the controller's remove
   handler restores the `wrangler.cattle.io/on-helm-chart-remove` finalizer as
   soon as it is stripped. Deleting the HelmChart then runs `helm uninstall`.
2. Strip the `wrangler.cattle.io/on-helm-chart-remove` finalizer from the
   HelmChart.
3. Delete the HelmChart. The live release stays in place.
4. Delete the chart's install leftovers in `kube-system`: the `helm-install-*`
   Job, its ServiceAccount, its cluster-admin ClusterRoleBinding, and its
   values Secret. Only the controller's own uninstall would remove them.

k3s records ownership in `objectset.rio.cattle.io` annotations instead of
ownerReferences, so no garbage collection happens. k3s's AddOn objects stay
until a test shows that deleting one leaves the objects it applied in place.

Flux HelmReleases also skip CRD upgrades by default. Traefik's HelmRelease sets
`install.crds` and `upgrade.crds` to `CreateReplace`, which retires the
committed CRD file. cert-manager templates its CRDs via `crds.enabled`, so Helm
already upgrades them.

`infrastructure-controllers` health-checks only its HelmReleases instead of
waiting on everything it applies. Otherwise, a chart repository index outage
would count as a failure.

Until dependency triage is automated, Traefik and cert-manager updates wait for
review like the monitoring stack.

## Consequences

- Flux applies every cluster dependency, and Renovate's flux manager updates it.
- If a controller upgrade fails, or a config fails to apply or decrypt, app
  syncs wait until the problem is fixed or rolled back. Running workloads keep
  running. This order is intentional because apps need ingress and TLS.
- A fresh cluster comes up from NixOS and Git. Flux installs the controllers,
  then their config, then the apps.
- The host-tied Services (headscale and refinery's database) and the app repos'
  `ci-deploy` RBAC can move to `k8s/` like `k8s/wger/db.yaml` did. That leaves
  k3s's manifests directory for the Flux bootstrap alone.
