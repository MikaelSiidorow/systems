{ pkgs, username, ... }:
let
  dockerHost = "unix:///run/user/1000/docker.sock";
in
{
  # Rootless, so containers get no more access than the agents T3 runs as
  # the user; the docker group would be root without a sudo password.
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
    daemon.settings.log-opts.max-size = "10m";
  };

  # T3 starts terminals and agents itself, without a login shell.
  systemd.services.t3code = {
    path = [ pkgs.docker ];
    environment.DOCKER_HOST = dockerHost;
  };

  # Volumes stay, since they hold the dev databases.
  systemd.user.services.docker-prune = {
    description = "Prune unused Docker images, containers and networks";
    unitConfig.ConditionUser = username;
    environment.DOCKER_HOST = dockerHost;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.docker}/bin/docker system prune --all --force --filter until=168h";
    };
  };
  systemd.user.timers.docker-prune = {
    wantedBy = [ "timers.target" ];
    unitConfig.ConditionUser = username;
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Prebuilt binaries (Playwright's browsers, npm and LSP downloads) expect a
  # generic Linux loader and libraries.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
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
    ];
  };
}
