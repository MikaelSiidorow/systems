{
  config,
  lib,
  username,
  ...
}:
{
  # Saha, a local agent-session console under development, runs its ingest as
  # a dev process on 127.0.0.1:4319, not as a service. This sends it every
  # agent signal as sent, before the T3 filter and content stripping; it stays
  # on this host. monitoring.nix routes the agents' receiver here when on.
  options.services.saha-export.enable = lib.mkEnableOption "sending agent telemetry from Hestia's Alloy to Saha's local ingest";

  config = lib.mkIf config.services.saha-export.enable {
    # Must match the hash Saha stores for its ingest user. Owned by the user
    # so Saha's dev tooling can read the same copy.
    sops.secrets.saha-ingest-token = {
      sopsFile = ../../../secrets/saha.yaml;
      owner = username;
      mode = "0400";
      restartUnits = [ "alloy.service" ];
    };

    systemd.services.alloy.serviceConfig.LoadCredential = [
      "saha-ingest-token:${config.sops.secrets.saha-ingest-token.path}"
    ];

    environment.etc."alloy/config.alloy".text = ''
      // Short batches keep Saha's view live.
      otelcol.processor.batch "saha" {
        timeout = "1s"

        output {
          metrics = [otelcol.exporter.otlphttp.saha.input]
          logs    = [otelcol.exporter.otlphttp.saha.input]
          traces  = [otelcol.exporter.otlphttp.saha.input]
        }
      }

      local.file "saha_token" {
        filename  = sys.env("CREDENTIALS_DIRECTORY") + "/saha-ingest-token"
        is_secret = true
      }

      otelcol.auth.bearer "saha" {
        token = local.file.saha_token.content
      }

      // While Saha is down, batches wait on disk in their own files (the
      // storage keys them by exporter and signal). 512 MiB holds about 6 h of
      // unfiltered T3 (~185k spans/h); past that, new batches are dropped,
      // and the raw archive covers the gap through replay.
      otelcol.exporter.otlphttp "saha" {
        client {
          endpoint = "http://127.0.0.1:4319"
          auth     = otelcol.auth.bearer.saha.handler
        }

        sending_queue {
          sizer      = "bytes"
          queue_size = 536870912
          storage    = otelcol.storage.file.queue.handler
        }

        retry_on_failure {
          max_elapsed_time = "6h"
        }
      }
    '';
  };
}
