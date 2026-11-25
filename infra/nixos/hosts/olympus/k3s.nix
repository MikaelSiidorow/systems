{ config, pkgs, ... }:

let
  manifestDir = "/var/lib/rancher/k3s/server/manifests";
in
{
  # K3s - Lightweight Kubernetes
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--disable=traefik" # Flux deploys Traefik (k8s/infrastructure/)
      "--tls-san=100.64.0.1" # Allow API access over Tailscale VPN
      # The node keeps the host's old name: local-path volumes are pinned to
      # the node name, so a node called olympus would start without its data.
      "--node-name=k8s-server"
    ];
  };

  # k3s applies only the Flux bootstrap; Flux deploys everything else from
  # k8s/ (docs/adr/0001-nixos-bootstraps-only-flux.md).
  systemd.tmpfiles.rules = [
    "L+ ${manifestDir}/flux-operator-helmchart.yaml - - - - ${./flux-operator-helmchart.yaml}"
    "L+ ${manifestDir}/flux-instance.yaml - - - - ${./flux-instance.yaml}"
    # Manifests k3s used to apply. Removing a file leaves what k3s applied
    # from it. Flux took over what is still needed; Argo CD was uninstalled
    # by hand, and the other HelmCharts were detached by hand so deleting
    # them didn't uninstall their releases.
    "r ${manifestDir}/traefik-crds.yaml - - - -"
    "r ${manifestDir}/traefik-helmchart.yaml - - - -"
    "r ${manifestDir}/cert-manager-helmchart.yaml - - - -"
    "r ${manifestDir}/cluster-issuer.yaml - - - -"
    "r ${manifestDir}/argocd-helmchart.yaml - - - -"
    "r ${manifestDir}/argocd-bootstrap.yaml - - - -"
    "r ${manifestDir}/headscale-service.yaml - - - -"
    "r ${manifestDir}/refinery-db-service.yaml - - - -"
    "r ${manifestDir}/wger-db-service.yaml - - - -"
    "r ${manifestDir}/ci-deploy-rbac.yaml - - - -"
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
