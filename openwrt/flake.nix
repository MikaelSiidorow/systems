{
  description = "OpenWrt firmware and configuration for the home routers";

  # Own lock: OpenWrt republishes package indexes often, so these inputs move
  # daily, independent of the servers in ../infra.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Build reproducible OpenWrt firmware images from upstream ImageBuilder releases.
    openwrt-imagebuilder = {
      url = "github:astro/nix-openwrt-imagebuilder";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Apply semi-declarative OpenWrt UCI configuration over SSH.
    dewclaw = {
      url = "github:MakiseKurisu/dewclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      dewclaw,
      openwrt-imagebuilder,
      ...
    }:
    {
      apps.x86_64-linux = {
        cerberus-deploy = {
          type = "app";
          program = "${self.packages.x86_64-linux.cerberus-deploy}/bin/deploy-r6220";
          meta.description = "Deploy the Cerberus OpenWrt configuration";
        };
        hermes-deploy = {
          type = "app";
          program = "${self.packages.x86_64-linux.hermes-deploy}/bin/deploy-archer-c6-v2";
          meta.description = "Deploy the Hermes OpenWrt configuration";
        };
      };

      packages.x86_64-linux =
        let
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
        in
        {
          cerberus-firmware = pkgs.callPackage ./r6220/firmware.nix {
            inherit openwrt-imagebuilder;
          };
          cerberus-deploy = pkgs.callPackage dewclaw {
            configuration = ./r6220/config.nix;
          };
          hermes-firmware = pkgs.callPackage ./archer-c6-v2/firmware.nix {
            inherit openwrt-imagebuilder;
          };
          hermes-deploy = pkgs.callPackage dewclaw {
            configuration = ./archer-c6-v2/config.nix;
          };
        };
    };
}
