{ config, pkgs, ... }:

let
  manifestDir = "/var/lib/rancher/k3s/server/manifests";

  traefikChart = pkgs.writeText "traefik-helmchart.yaml" ''
    apiVersion: helm.cattle.io/v1
    kind: HelmChart
    metadata:
      name: traefik
      namespace: kube-system
    spec:
      chart: traefik
      repo: https://traefik.github.io/charts
      targetNamespace: traefik
      createNamespace: true
      version: 41.6.1
      valuesContent: |-
        ports:
          web:
            http:
              redirections:
                entryPoint:
                  to: websecure
                  scheme: https
  '';

  certManagerChart = pkgs.writeText "cert-manager-helmchart.yaml" ''
    apiVersion: helm.cattle.io/v1
    kind: HelmChart
    metadata:
      name: cert-manager
      namespace: kube-system
    spec:
      chart: cert-manager
      repo: https://charts.jetstack.io
      targetNamespace: cert-manager
      createNamespace: true
      version: v1.21.2
      valuesContent: |-
        crds:
          enabled: true
  '';

  argocdChart = pkgs.writeText "argocd-helmchart.yaml" ''
    apiVersion: helm.cattle.io/v1
    kind: HelmChart
    metadata:
      name: argocd
      namespace: kube-system
    spec:
      chart: argo-cd
      repo: https://argoproj.github.io/argo-helm
      targetNamespace: argocd
      createNamespace: true
      version: 10.9.6
      valuesContent: |-
        configs:
          params:
            server.insecure: "true" # TLS terminated by Traefik ingress
  '';

  argocdBootstrap = pkgs.writeText "argocd-bootstrap.yaml" ''
    apiVersion: argoproj.io/v1alpha1
    kind: Application
    metadata:
      name: bootstrap
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/MikaelSiidorow/systems.git
        targetRevision: main
        path: k8s/apps
      destination:
        server: https://kubernetes.default.svc
        namespace: argocd
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
  '';

  # Host service endpoints — managed by NixOS instead of ArgoCD because
  # ArgoCD excludes Endpoints/EndpointSlice resources by default.
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

  clusterIssuer = pkgs.writeText "cluster-issuer.yaml" ''
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-prod
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: mikael@siidorow.com
        privateKeySecretRef:
          name: letsencrypt-prod-account-key
        solvers:
          - http01:
              ingress:
                ingressClassName: traefik
    ---
    apiVersion: cert-manager.io/v1
    kind: ClusterIssuer
    metadata:
      name: letsencrypt-dns
    spec:
      acme:
        server: https://acme-v02.api.letsencrypt.org/directory
        email: mikael@siidorow.com
        privateKeySecretRef:
          name: letsencrypt-dns-account-key
        solvers:
          - dns01:
              cloudflare:
                apiTokenSecretRef:
                  name: cloudflare-api-token
                  key: api-token
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
    ];
  };

  # Auto-deploy infrastructure manifests via K3s
  systemd.tmpfiles.rules = [
    # Helm never upgrades a chart's CRDs, so the traefik chart's CRDs are
    # committed (see .github/scripts/traefik-crds.sh) and applied by k3s.
    "L+ ${manifestDir}/traefik-crds.yaml - - - - ${./traefik-crds.yaml}"
    "L+ ${manifestDir}/traefik-helmchart.yaml - - - - ${traefikChart}"
    "L+ ${manifestDir}/cert-manager-helmchart.yaml - - - - ${certManagerChart}"
    "L+ ${manifestDir}/cluster-issuer.yaml - - - - ${clusterIssuer}"
    "L+ ${manifestDir}/argocd-helmchart.yaml - - - - ${argocdChart}"
    "L+ ${manifestDir}/argocd-bootstrap.yaml - - - - ${argocdBootstrap}"
    "L+ ${manifestDir}/headscale-service.yaml - - - - ${headscaleService}"
    "L+ ${manifestDir}/refinery-db-service.yaml - - - - ${refineryDbService}"
    # wger's namespace and database service are managed by Kubernetes Terraform.
    "r ${manifestDir}/wger-db-service.yaml - - - -"
    "L+ ${manifestDir}/ci-deploy-rbac.yaml - - - - ${ciDeployRbac}"
  ];

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
