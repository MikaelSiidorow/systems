{
  config,
  pkgs,
  username,
  ...
}:
{
  imports = [
    ./cli-proxy-api.nix
    ./t3code.nix
    ./home.nix
    ./home-assistant.nix
    ./monitoring.nix
    ./reverse-proxy.nix
    ./zigbee.nix
  ];

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "ntfs" ];
    # Caddy binds the tailnet address, which can appear after Caddy starts.
    kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;
  };

  networking = {
    hostName = "hestia";
    networkmanager.enable = false;
  };

  time.timeZone = "Europe/Helsinki";

  # Hestia builds and deploys the flake-pinned router configurations.
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # llm-agents packages (Codex is a heavy Rust build) are only cached here.
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
    # The defaults (12 jobs x all cores) likely froze Hestia during a remote deploy build.
    max-jobs = 2;
    cores = 6;
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Dewclaw invokes the ordinary OpenSSH client when deploying the routers.
  # Select Hestia's dedicated keys explicitly because they intentionally do
  # not use default personal-key filenames.
  programs.ssh.extraConfig = ''
    Host github.com
      User git
      IdentityFile ${config.sops.secrets.github-ssh-key.path}
      IdentitiesOnly yes

    Host device 192.168.67.1 192.168.67.2
      IdentityFile ${config.sops.secrets.router-deploy-ssh-key.path}
      IdentitiesOnly yes
  '';

  # Pin GitHub's published Ed25519 host key so unattended Git operations do
  # not depend on an interactive first-connection prompt.
  programs.ssh.knownHosts."github.com" = {
    hostNames = [ "github.com" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
  };

  programs.git = {
    enable = true;
    config.user = {
      name = "Mikael Siidorow";
      email = "mikael@siidorow.com";
    };
  };

  sops.secrets.github-ssh-key = {
    owner = username;
    group = "users";
    mode = "0400";
  };

  sops.secrets.router-deploy-ssh-key = {
    owner = username;
    group = "users";
    mode = "0600";
  };

  # Join Hestia to the existing Headscale tailnet once with `tailscale up`.
  # The persisted node state keeps that enrollment, while NixOS owns the
  # forwarding and route-advertisement settings needed to reach the home LAN.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-routes=192.168.67.0/24" ];
  };

  # Tailscale subnet routers benefit from forwarding UDP GRO on the physical
  # interface. Apply the upstream-recommended flags on every boot.
  systemd.services.tailscale-udp-gro-forwarding = {
    description = "Optimize UDP GRO forwarding for Tailscale";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    before = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool -K enp31s0 rx-udp-gro-forwarding on rx-gro-list off";
    };
  };

  users.users.${username} = {
    isNormalUser = true;
    description = "Mikael Siidorow";
    linger = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBHSw1Hq0dCnEC2j78BqNKzP+hrn+MLppWELfHgVNCaG"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBHSw1Hq0dCnEC2j78BqNKzP+hrn+MLppWELfHgVNCaG"
  ];

  environment.systemPackages = with pkgs; [
    ddrescue
    ntfs3g
    rsync
    smartmontools
    vim
  ];

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # This is the release used for the initial installation. Do not change it.
  system.stateVersion = "26.05";
}
