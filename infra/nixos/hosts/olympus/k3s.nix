{ config, pkgs, ... }:

let
  manifestDir = "/var/lib/rancher/k3s/server/manifests";

  # Host service endpoints for services that run on olympus itself.
  headscaleService = pkgs.writeText "headscale-service.yaml" ''
    apiVersion: v1
    kind: Namespace
    metadata:
      name: headscale
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: headscale
      namespace: headscale
    spec:
      ports:
        - port: 8080
          targetPort: 8080
    ---
    apiVersion: discovery.k8s.io/v1
    kind: EndpointSlice
    metadata:
      name: headscale
      namespace: headscale
      labels:
        kubernetes.io/service-name: headscale
    addressType: IPv4
    ports:
      - port: 8080
    endpoints:
      - addresses:
          - 10.42.0.1
  '';

  ciDeployRbac = pkgs.writeText "ci-deploy-rbac.yaml" ''
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: ci-deploy
      namespace: refinery
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: ci-deploy-token
      namespace: refinery
      annotations:
        kubernetes.io/service-account.name: ci-deploy
    type: kubernetes.io/service-account-token
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: ci-deploy
      namespace: refinery
    rules:
      - apiGroups: ["apps"]
        resources: ["deployments"]
        verbs: ["get", "list", "watch", "patch"]
        resourceNames: ["refinery-app", "refinery-zero"]
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: ci-deploy
      namespace: refinery
    subjects:
      - kind: ServiceAccount
        name: ci-deploy
        namespace: refinery
    roleRef:
      kind: Role
      name: ci-deploy
      apiGroup: rbac.authorization.k8s.io
    ---
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: ci-deploy
      namespace: wger
    ---
    apiVersion: v1
    kind: Secret
    metadata:
      name: ci-deploy-token
      namespace: wger
      annotations:
        kubernetes.io/service-account.name: ci-deploy
    type: kubernetes.io/service-account-token
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: ci-deploy
      namespace: wger
    rules:
      - apiGroups: ["apps"]
        resources: ["deployments"]
        verbs: ["get", "list", "watch", "patch"]
        resourceNames: ["wger-web", "wger-celery-worker", "wger-celery-beat"]
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: ci-deploy
      namespace: wger
    subjects:
      - kind: ServiceAccount
        name: ci-deploy
        namespace: wger
    roleRef:
      kind: Role
      name: ci-deploy
      apiGroup: rbac.authorization.k8s.io
  '';

  refineryDbService = pkgs.writeText "refinery-db-service.yaml" ''
    apiVersion: v1
    kind: Service
    metadata:
      name: refinery-db
      namespace: refinery
    spec:
      ports:
        - port: 5432
          targetPort: 5432
    ---
    apiVersion: discovery.k8s.io/v1
    kind: EndpointSlice
    metadata:
      name: refinery-db
      namespace: refinery
      labels:
        kubernetes.io/service-name: refinery-db
    addressType: IPv4
    ports:
      - port: 5432
    endpoints:
      - addresses:
          - 10.42.0.1
  '';
in
{
  # K3s - Lightweight Kubernetes
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik" # Deploy our own Traefik via HelmChart CRD
      "--tls-san=100.64.0.1" # Allow API access over Tailscale VPN
      # The node keeps the host's old name: local-path volumes are pinned to
      # the node name, so a node called olympus would start without its data.
      "--node-name=k8s-server"
    ];
  };

  # Auto-deploy infrastructure manifests via K3s
  systemd.tmpfiles.rules = [
    # Helm never upgrades a chart's CRDs, so the traefik chart's CRDs are
    # committed (see .github/scripts/traefik-crds.sh) and applied by k3s.
    "L+ ${manifestDir}/traefik-crds.yaml - - - - ${./traefik-crds.yaml}"
    "L+ ${manifestDir}/traefik-helmchart.yaml - - - - ${./traefik-helmchart.yaml}"
    # Flux installs cert-manager and the ClusterIssuers (k8s/infrastructure/).
    # Removing a file leaves what k3s applied; the HelmChart was marked
    # unmanaged and deleted by hand, since deleting a managed one uninstalls
    # the release (docs/adr/0001-nixos-bootstraps-only-flux.md).
    "r ${manifestDir}/cert-manager-helmchart.yaml - - - -"
    "r ${manifestDir}/cluster-issuer.yaml - - - -"
    # Argo CD is gone; Flux deploys k8s/. Removing a file leaves what k3s
    # applied from it, so the release was uninstalled by hand.
    "r ${manifestDir}/argocd-helmchart.yaml - - - -"
    "r ${manifestDir}/argocd-bootstrap.yaml - - - -"
    "L+ ${manifestDir}/flux-operator-helmchart.yaml - - - - ${./flux-operator-helmchart.yaml}"
    "L+ ${manifestDir}/flux-instance.yaml - - - - ${./flux-instance.yaml}"
    "L+ ${manifestDir}/headscale-service.yaml - - - - ${headscaleService}"
    "L+ ${manifestDir}/refinery-db-service.yaml - - - - ${refineryDbService}"
    # wger's namespace and database service are in k8s/wger, deployed by Flux.
    "r ${manifestDir}/wger-db-service.yaml - - - -"
    "L+ ${manifestDir}/ci-deploy-rbac.yaml - - - - ${ciDeployRbac}"
  ];

  # Hand olympus's host age key to Flux so kustomize-controller can decrypt
  # SOPS-encrypted Secrets in k8s/. The key stays on disk and never enters
  # the Nix store.
  systemd.services.flux-sops-age = {
    description = "Sync olympus's age key into the flux-system sops-age Secret";
    after = [
      "k3s.service"
      "sops-age-key.service"
    ];
    requires = [ "k3s.service" ];
    wants = [ "sops-age-key.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = 180;
    };
    script = ''
      set -o pipefail
      key_file=${config.sops.age.keyFile}
      if [ ! -s "$key_file" ]; then
        echo "$key_file is missing or empty" >&2
        exit 1
      fi

      kubectl=${config.services.k3s.package}/bin/k3s
      for _ in $(${pkgs.coreutils}/bin/seq 1 60); do
        if (
          "$kubectl" kubectl get namespace flux-system >/dev/null 2>&1 \
            || "$kubectl" kubectl create namespace flux-system >/dev/null 2>&1 \
            || "$kubectl" kubectl get namespace flux-system >/dev/null 2>&1
        ) && "$kubectl" kubectl create secret generic sops-age \
          --namespace=flux-system \
          --from-file=age.agekey="$key_file" \
          --dry-run=client -o yaml \
          | "$kubectl" kubectl apply --server-side --force-conflicts --field-manager=flux-sops-age -f -; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 2
      done

      echo "Timed out syncing flux-system/sops-age" >&2
      exit 1
    '';
  };

  systemd.paths.flux-sops-age = {
    description = "Watch olympus's age key for changes and re-sync flux-system/sops-age";
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathChanged = config.sops.age.keyFile;
      Unit = "flux-sops-age.service";
    };
  };

  # Ensure k3s can manage iptables
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Alias for convenience
  environment.shellAliases = {
    k = "kubectl";
  };

  # Kubeconfig for root
  environment.variables = {
    KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  };
}
