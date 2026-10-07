{
  config,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ./disko.nix
    ./k3s.nix
    ./headscale.nix
  ];

  # System
  system.stateVersion = "25.11";
  nixpkgs.config.allowUnfree = true;

  # Nix settings
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Boot - disko handles grub configuration for BIOS/GPT

  # Hetzner Cloud VM settings
  boot.initrd.availableKernelModules = [
    "ata_piix"
    "virtio_pci"
    "virtio_scsi"
    "xhci_pci"
    "sd_mod"
    "sr_mod"
  ];
  boot.kernelModules = [ ];

  # Networking
  networking = {
    hostName = "k8s-server";
    useDHCP = lib.mkDefault true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22 # SSH
        80 # HTTP
        443 # HTTPS
      ];
      interfaces."cni0".allowedTCPPorts = [
        5432 # PostgreSQL from K8s pods only
      ];
    };
  };

  # Timezone
  time.timeZone = "Europe/Helsinki";

  # Users
  users.users.root = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBHSw1Hq0dCnEC2j78BqNKzP+hrn+MLppWELfHgVNCaG" # personal
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOia2sNQKFyftl4aDTHLGRhL3l54oPQRB49LVLWyevg7" # deploy key
    ];
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # PostgreSQL
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    settings = {
      listen_addresses = lib.mkForce "127.0.0.1,10.42.0.1";
      wal_level = "logical";
    };
    authentication = ''
      # K8s pod network (default CIDR for K3s)
      host all all 10.42.0.0/16 scram-sha-256
      # K3s service network
      host all all 10.43.0.0/16 scram-sha-256
    '';
    ensureDatabases = [
      "refinery"
      "wger"
    ];
    ensureUsers = [
      {
        name = "refinery";
        ensureDBOwnership = true;
      }
      {
        name = "wger";
        ensureDBOwnership = true;
        ensureClauses = {
          login = true;
          replication = true;
          createrole = true;
        };
      }
      {
        name = "powersync_storage";
        ensureClauses.login = true;
      }
      # zero-cache manages event triggers for schema change tracking, and only
      # a superuser can create or alter them. The refinery app keeps its own
      # non-superuser role. CI sets the password.
      {
        name = "zero";
        ensureClauses = {
          login = true;
          superuser = true;
        };
      }
    ];
    # Runs only on first cluster init (fresh deploy)
    initialScript = pkgs.writeText "pg-init.sql" ''
      ALTER ROLE refinery WITH REPLICATION;
    '';
  };

  # PostgreSQL listens on the K3s bridge address, which is created
  # asynchronously after k3s starts. Avoid a boot-time bind failure.
  systemd.services.wait-for-k3s-cni = {
    description = "Wait for the K3s CNI bridge address";
    after = [ "k3s.service" ];
    requires = [ "k3s.service" ];
    before = [ "postgresql.service" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = 130;
    };
    script = ''
      for attempt in {1..120}; do
        if ${pkgs.iproute2}/bin/ip -4 -o address show dev cni0 2>/dev/null \
          | ${pkgs.gnugrep}/bin/grep -Fq ' 10.42.0.1/'; then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done

      echo "Timed out waiting for 10.42.0.1 on cni0" >&2
      exit 1
    '';
  };

  systemd.services.postgresql = {
    after = [ "wait-for-k3s-cni.service" ];
    requires = [ "wait-for-k3s-cni.service" ];
  };

  # Logical replication and PowerSync role membership must also be reconciled
  # on existing clusters.
  # Wger's migration creates this publication itself when it is absent, but
  # PostgreSQL requires a superuser for FOR ALL TABLES publications. Create it
  # here as postgres so the application role does not need superuser access.
  systemd.services.postgresql-grant-replication = {
    description = "Reconcile PostgreSQL replication and PowerSync prerequisites";
    after = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    requires = [
      "postgresql.service"
      "postgresql-setup.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };
    script = ''
      ${config.services.postgresql.package}/bin/psql -c "ALTER ROLE refinery WITH REPLICATION;"
      ${config.services.postgresql.package}/bin/psql --dbname=wger --set=ON_ERROR_STOP=1 <<'SQL'
      GRANT powersync_storage TO wger WITH ADMIN TRUE, SET TRUE;

      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_publication WHERE pubname = 'powersync'
        ) THEN
          CREATE PUBLICATION powersync FOR ALL TABLES;
        END IF;
      END
      $$;
      SQL
    '';
  };

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    curl
    wget
    jq
    k9s
    kubectl
    kubernetes-helm
  ];
}
