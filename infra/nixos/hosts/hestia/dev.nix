{
  options,
  pkgs,
  inputs,
  username,
  ...
}:
let
  dockerHost = "unix:///run/user/1000/docker.sock";
  # Playwright checks the browsers' libraries with ldd, which cannot see the
  # nix-ld ones below, and refuses to launch browsers that run fine.
  playwright.PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
in
{
  # Rootless, so containers get no more access than the agents T3 runs as
  # the user; the docker group would be root without a sudo password.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
    daemon.settings.log-opts.max-size = "10m";
  };

  # Agent containers run here, outside t3code.service's memory cap, and have
  # peaked at 5G. Cap them too, so a container OOMs before the host does.
  systemd.user.services.docker.serviceConfig = {
    MemoryHigh = "5G";
    MemoryMax = "6G";
  };

  # T3 starts terminals and agents itself, without a login shell.
  systemd.services.t3code = {
    path = [ pkgs.docker ];
    environment = {
      DOCKER_HOST = dockerHost;
      inherit (playwright) PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS;
    };
  };

  environment.variables = playwright;

  # Lets agents here drive Amp threads (`amp threads continue <id>`).
  # From llm-agents: nixpkgs stable trails Amp releases by months.
  environment.systemPackages = [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.amp
  ];

  # Volumes stay, since they hold the dev databases. The age filter spares a
  # week of build cache, so a size cap stops Rust builds filling the disk.
  systemd.user.services.docker-prune = {
    description = "Prune unused Docker images, containers, networks and build cache";
    unitConfig.ConditionUser = username;
    environment.DOCKER_HOST = dockerHost;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [
        "${pkgs.docker}/bin/docker system prune --all --force --filter until=168h"
        "${pkgs.docker}/bin/docker builder prune --force --max-used-space 20GB"
      ];
    };
  };
  systemd.user.timers.docker-prune = {
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = username;
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Prebuilt binaries (Playwright's browsers, npm and LSP downloads) expect a
  # generic Linux loader and libraries.
  programs.nix-ld = {
    enable = true;
    # Setting the list replaces the defaults (libstdc++, zlib, openssl, ...).
    libraries =
      options.programs.nix-ld.libraries.default
      ++ (with pkgs; [
        # Playwright Chromium and Firefox.
        alsa-lib
        at-spi2-atk
        at-spi2-core
        atk
        cairo
        cups
        dbus
        dbus-glib
        expat
        fontconfig
        freetype
        gdk-pixbuf
        glib
        gtk3
        libdrm
        libgbm
        libxkbcommon
        mesa
        nspr
        nss
        pango
        systemd
        libx11
        libxcomposite
        libxcursor
        libxdamage
        libxext
        libxfixes
        libxi
        libxrandr
        libxrender
        libxtst
        libxcb
        libxshmfence
        libxscrnsaver
      ]);
  };
}
