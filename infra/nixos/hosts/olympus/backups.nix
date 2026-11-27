# Nightly restic backup to Hestia's append-only rest-server
# (docs/adr/0003-backups-with-restic.md).
{ config, pkgs, ... }:
let
  postgres = config.services.postgresql.package;
  dumpDir = "/var/backup/postgresql";

  # Runs a command as postgres without the rest-server login the unit's
  # environment file sets.
  asPostgres = "${pkgs.coreutils}/bin/env -u RESTIC_REST_USERNAME -u RESTIC_REST_PASSWORD ${pkgs.util-linux}/bin/runuser -u postgres --";

  # One custom-format dump per database, plus the roles. Uncompressed, so
  # restic can deduplicate unchanged data between nights and compress it itself.
  dumpPostgres = pkgs.writeShellScript "dump-postgres" ''
    set -euo pipefail

    rm -rf ${dumpDir}
    install -d -m 0700 -o postgres -g postgres ${dumpDir}

    ${asPostgres} ${postgres}/bin/pg_dumpall --globals-only --file=${dumpDir}/globals.sql </dev/null

    ${asPostgres} ${postgres}/bin/psql --no-align --tuples-only --set=ON_ERROR_STOP=1 \
      --command="SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn ORDER BY datname" \
      </dev/null \
      | while IFS= read -r db; do
          ${asPostgres} ${postgres}/bin/pg_dump --format=custom --compress=0 \
            --file="${dumpDir}/$db.dump" "$db" </dev/null
        done
  '';
in
{
  sops.secrets.restic-password = { };
  sops.secrets.restic-rest-server-password = { };
  sops.templates."restic-rest-server.env".content = ''
    RESTIC_REST_USERNAME=olympus
    RESTIC_REST_PASSWORD=${config.sops.placeholder.restic-rest-server-password}
  '';

  services.restic.backups.hestia = {
    repository = "rest:http://100.64.0.3:8000/olympus/";
    passwordFile = config.sops.secrets.restic-password.path;
    environmentFile = config.sops.templates."restic-rest-server.env".path;
    initialize = true;
    backupPrepareCommand = "${dumpPostgres}";
    # The dumps hold every row and the role password hashes; keep them on
    # disk only while restic reads them.
    backupCleanupCommand = "rm -rf ${dumpDir}";
    paths = [ dumpDir ];
    # Hestia prunes; the rest-server is append-only, so olympus cannot.
    pruneOpts = [ ];
    timerConfig = {
      OnCalendar = "03:00";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };

  systemd.services.restic-backups-hestia = {
    after = [
      "postgresql.service"
      "tailscaled.service"
    ];
    requires = [ "postgresql.service" ];
  };
}
