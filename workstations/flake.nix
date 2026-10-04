{
  description = "Mikael's multi-platform Nix configuration";

  inputs = {
    # Default package set: stable release branch for broad desktop/system use.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fast lane for browsers and selected fast-moving desktop apps.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Darwin (macOS) support; keep the release aligned with nixpkgs.
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager for user environment
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative secret management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Prebuilt nix-index database and comma command lookup
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Maintained hardware defaults and quirks for the ThinkPad X1 Carbon Gen 9.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Homebrew integration for macOS. Taps are pinned for reproducibility.
    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew/main";

    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };

    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };

    # Nix User Repository (Firefox extensions, etc.)
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Claude Code with automatic updates
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Codex CLI with automatic updates
    codex-cli-nix = {
      url = "github:sadjow/codex-cli-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Keep client and server together; Renovate updates both revision pins.
    llm-agents.url = "github:numtide/llm-agents.nix/83984ebbbe5322b261d9fdc24eb15cf44f23abec";

    # OpenCode with automatic updates (for NixOS/Linux)
    opencode-nix = {
      url = "github:dan-online/opencode-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # CachyOS kernel for NixOS (performance-tuned, BORE scheduler)
    nix-cachyos-kernel = {
      url = "github:xddxdd/nix-cachyos-kernel/release";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      nix-darwin,
      home-manager,
      nixos-hardware,
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
      nur,
      plasma-manager,
      nix-cachyos-kernel,
      ...
    }@inputs:
    let
      inherit (nixpkgs) lib;

      # Linux home-manager (tpad, Pop!_OS) account.
      username = "mikaelsiidorow";
      # macOS account (different local username).
      darwinUsername = "mikael";

      supportedSystems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      mkApp = program: description: {
        type = "app";
        inherit program;
        meta.description = description;
      };

      mkPkgsUnstable =
        system:
        import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };

      # Custom mergiraf with tree-sitter-po grammar for PO/gettext merge support
      mergirafOverlay = final: _: {
        mergiraf = final.callPackage ./pkgs/mergiraf-custom { };
      };

      # Skip direnv's checkPhase on darwin. Its test suite forks subshells
      # that hang inside nix's macOS sandbox, and aarch64-darwin binary
      # caches often lag behind, forcing source builds that deadlock.
      direnvOverlay = _: prev: {
        direnv = prev.direnv.overrideAttrs (_: {
          doCheck = false;
        });
      };

      # Darwin hosts: attr key is the LocalHostName (must match
      # `scutil --get LocalHostName`, which is what darwin-rebuild uses
      # to resolve the default flake target). `hostname` is the
      # directory under hosts/.
      darwinHosts = {
        "Mikael-MacBook-Pro-H7D6Q4TMVY" = {
          system = "aarch64-darwin";
          hostname = "mbp";
        };
      };

      # Helper function to create a darwin system
      mkDarwinSystem =
        {
          system,
          username,
          hostname,
          extraModules ? [ ],
        }:
        let
          pkgs-unstable = mkPkgsUnstable system;
        in
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              inputs
              pkgs-unstable
              username
              ;
          };
          modules = [
            # Custom package overlays
            {
              nixpkgs.overlays = [
                mergirafOverlay
                direnvOverlay
                nur.overlays.default
              ];
            }

            {
              imports = [ ./hosts/${hostname} ];
              nixpkgs.hostPlatform = system;
            }

            # Homebrew integration
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                enable = true;
                user = username;
                # Pinning homebrew-core enables offline mode.
                taps = {
                  "homebrew/homebrew-core" = homebrew-core;
                  "homebrew/homebrew-cask" = homebrew-cask;
                };
                mutableTaps = false;
                autoMigrate = true;
              };
            }

            # Home-manager integration
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "backup";
                extraSpecialArgs = {
                  inherit inputs pkgs-unstable hostname;
                  isDarwin = true;
                  isNixOS = false;
                };
                users.${username} = import ./home;
              };
            }
          ]
          ++ extraModules;
        };

      # Helper function to create a NixOS system
      mkNixosSystem =
        {
          system,
          hostname,
          extraModules ? [ ],
        }:
        let
          pkgs-unstable = mkPkgsUnstable system;
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit
              self
              inputs
              pkgs-unstable
              username
              ;
          };
          modules = [
            # Custom package overlays
            {
              nixpkgs.overlays = [
                mergirafOverlay
                nur.overlays.default
                nix-cachyos-kernel.overlays.pinned
              ];
            }

            # Host-specific configuration
            ./hosts/${hostname}

            # Home-manager integration
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "backup";
                sharedModules = [ plasma-manager.homeModules.plasma-manager ];
                extraSpecialArgs = {
                  inherit inputs pkgs-unstable hostname;
                  isDarwin = false;
                  isNixOS = true;
                };
                users.${username} = import ./home;
              };
            }
          ]
          ++ extraModules;
        };

      # Helper function to create a home-manager standalone config
      mkHomeConfig =
        {
          system,
          hostname,
          extraModules ? [ ],
        }:
        let
          pkgs-unstable = mkPkgsUnstable system;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              nur.overlays.default
            ];
          };
          extraSpecialArgs = {
            inherit
              self
              inputs
              pkgs-unstable
              hostname
              ;
            isDarwin = false;
            isNixOS = false;
          };
          modules = [
            ./hosts/${hostname}
            ./home
            {
              home = {
                inherit username;
                homeDirectory = "/home/${username}";
              };
            }
          ]
          ++ extraModules;
        };
    in
    {
      # Darwin (macOS) configurations
      darwinConfigurations = builtins.mapAttrs (
        _: host:
        mkDarwinSystem {
          inherit (host) system hostname;
          username = darwinUsername;
        }
      ) darwinHosts;

      # Standalone package for testing: nix build .#packages.aarch64-darwin.mergiraf
      packages = builtins.listToAttrs (
        map (system: {
          name = system;
          value =
            let
              pkgs = import nixpkgs { inherit system; };
            in
            {
              mergiraf = pkgs.callPackage ./pkgs/mergiraf-custom { };
            };
        }) supportedSystems
      );

      # Pinned repository tooling used by the Makefile.
      devShells = builtins.listToAttrs (
        map (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          {
            name = system;
            value.checks = pkgs.mkShellNoCC {
              packages = with pkgs; [
                deadnix
                nixfmt
                oxfmt
                shellcheck
                shfmt
                statix
                treefmt
              ];
            };
          }
        ) supportedSystems
      );

      apps = builtins.listToAttrs (
        map (system: {
          name = system;
          value = {
            home-manager = mkApp "${home-manager.packages.${system}.home-manager}/bin/home-manager" "Run the locked Home Manager CLI";
          }
          // lib.optionalAttrs (lib.hasSuffix "darwin" system) {
            darwin-rebuild = mkApp "${nix-darwin.packages.${system}.darwin-rebuild}/bin/darwin-rebuild" "Run the locked nix-darwin rebuild CLI";
          };
        }) supportedSystems
      );
      # NixOS configurations
      nixosConfigurations = {
        "nixos-laptop" = mkNixosSystem {
          system = "x86_64-linux";
          hostname = "nixos-laptop";
          extraModules = [ nixos-hardware.nixosModules.lenovo-thinkpad-x1-9th-gen ];
        };

        # VM variant for testing — run: nix build .#nixosConfigurations.nixos-laptop-vm.config.system.build.vm
        # Then: ./result/bin/run-nixos-laptop-vm
        "nixos-laptop-vm" = mkNixosSystem {
          system = "x86_64-linux";
          hostname = "nixos-laptop";
          extraModules = [
            (
              {
                lib,
                modulesPath,
                ...
              }:
              {
                imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

                # Skip real hardware config (LUKS, UUIDs) — VM handles its own
                disabledModules = [ ./hosts/nixos-laptop/hardware-configuration.nix ];

                # VM settings
                virtualisation = {
                  memorySize = 4096;
                  cores = 4;
                  diskSize = 8192;
                  resolution = {
                    x = 1920;
                    y = 1080;
                  };
                  qemu.options = [
                    "-display gtk"
                  ];
                };

                # Placeholder filesystems for evaluation (overridden by VM module)
                fileSystems."/" = lib.mkForce {
                  device = "/dev/disk/by-label/nixos";
                  fsType = "ext4";
                };

                # ponytail: the VM previews Plasma, not alternate physical kernels.
                specialisation = lib.mkForce { };

                # Set a password for VM login (password: "test")
                users.users.${username}.initialHashedPassword =
                  "$y$j9T$63FtiwzFlRRMEGBFJ/QNd.$pXlcmADD4dqHv.3/k.78sBE9oBKFp75p9HPmRfoRcT.";

                # Auto-login to Plasma in the disposable VM.
                services.displayManager.autoLogin = {
                  enable = true;
                  user = username;
                };
              }
            )
          ];
        };
      };

      # Home-manager standalone configurations (for non-NixOS systems)
      homeConfigurations = {
        "mikaelsiidorow@tpad" = mkHomeConfig {
          system = "x86_64-linux";
          hostname = "tpad";
        };
      };

      # Formatter configuration for `nix fmt`
      formatter = {
        aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.nixfmt-tree;
        x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
      };
    };
}
