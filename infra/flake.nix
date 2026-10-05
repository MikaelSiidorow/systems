{
  description = "Infrastructure NixOS configurations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Home Assistant moves faster than the stable NixOS release.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Keep client and server together; Renovate updates both revision pins.
    llm-agents.url = "github:numtide/llm-agents.nix/ba24820b562c0e1ff95d283a2e2e1debcbcbad83";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager on Hestia, sharing modules/home/core with the workstations.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Prebuilt nix-index database, imported by modules/home/core.
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      deploy-rs,
      disko,
      sops-nix,
      ...
    }:
    {
      apps.x86_64-linux = {
        deploy = deploy-rs.apps.x86_64-linux.default;
      };

      nixosConfigurations = {
        k8s-server = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            ./nixos/hosts/k8s-server/configuration.nix
          ];
        };

        hestia = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit inputs;
            username = "mikaelsiidorow";
          };
          modules = [
            disko.nixosModules.disko
            ./nixos/hosts/hestia/disk-config.nix
            ./nixos/hosts/hestia/hardware-configuration.nix
            ./nixos/hosts/hestia/default.nix
          ];
        };
      };

      deploy = {
        nodes = {
          k8s-server = {
            hostname = "89.167.124.71";
            sshUser = "root";
            profiles.system = {
              user = "root";
              path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.k8s-server;
            };
          };

          hestia = {
            hostname = "hestia.home.arpa";
            sshUser = "root";
            profiles.system = {
              user = "root";
              path = deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.hestia;
            };
          };
        };
      };

      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
