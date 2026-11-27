# Receives olympus's nightly restic backups (docs/adr/0003-backups-with-restic.md).
{ config, ... }:
let
  tailnetAddress = "100.64.0.3";
  port = 8000;
in
{
  # Append-only: olympus can add snapshots but never delete them. Pruning runs
  # locally as the restic user against the repository directory, not through
  # the server, so every file stays readable by the server.
  services.restic.server = {
    enable = true;
    listenAddress = "${tailnetAddress}:${toString port}";
    appendOnly = true;
    # Each login reaches only the repository under its own name (/olympus/).
    privateRepos = true;
    htpasswd-file = config.sops.secrets.restic-rest-server-htpasswd.path;
  };

  # bcrypt `htpasswd -B` entry for the olympus login.
  sops.secrets.restic-rest-server-htpasswd = {
    owner = "restic";
    group = "restic";
    mode = "0400";
  };

  # The headscale ACL lets olympus (tag:infra) and your own devices reach this.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];
}
