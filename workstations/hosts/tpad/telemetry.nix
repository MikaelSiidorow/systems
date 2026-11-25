# Claude Code and Codex export to a local Alloy queue, which forwards to the
# cluster Alloy over the tailnet like Hestia's (infra/nixos/hosts/hestia/monitoring.nix).
# The laptop is often offline, so batches wait on disk and retry for a day.
# Raw OTLP is also archived in ~/.local/state/alloy/archive.
{ config, pkgs, ... }:
let
  alloyConfig = pkgs.writeText "config.alloy" ''
    otelcol.receiver.otlp "agents" {
      http {
        endpoint = "127.0.0.1:4318"
      }

      output {
        metrics = [otelcol.processor.batch.archive.input, otelcol.processor.batch.default.input]
        logs    = [otelcol.processor.batch.archive.input, otelcol.processor.attributes.content.input]
        traces  = [otelcol.processor.batch.archive.input, otelcol.processor.filter.content.input]
      }
    }

    ${import ../../../modules/agent-telemetry-alloy.nix "${config.xdg.stateHome}/alloy/archive"}

    otelcol.processor.batch "default" {
      output {
        metrics = [otelcol.exporter.otlphttp.cluster.input]
        logs    = [otelcol.exporter.otlphttp.cluster.input]
        traces  = [otelcol.exporter.otlphttp.cluster.input]
      }
    }

    // Lives under the service's state directory; compaction gives the disk
    // back once a backlog drains.
    otelcol.storage.file "queue" {
      compaction {
        on_start   = true
        on_rebound = true
      }
    }

    // Agent batches only, so a day offline fits well inside the queue. One
    // consumer drains in order, since the cluster turns delta metrics
    // cumulative and drops points that arrive out of order.
    otelcol.exporter.otlphttp "cluster" {
      client {
        endpoint = "http://100.64.0.1:4318"
      }

      sending_queue {
        queue_size    = 10000
        num_consumers = 1
        storage       = otelcol.storage.file.queue.handler
      }

      retry_on_failure {
        max_elapsed_time = "24h"
      }
    }
  '';
in
{
  agents.telemetry = {
    endpoint = "http://127.0.0.1:4318";
    host = "tpad";
  };

  systemd.user.services.alloy = {
    Unit.Description = "Alloy queue for agent telemetry";
    Service = {
      # otelcol.storage.file and otelcol.exporter.file are public preview.
      # State, the queue and the archive live in ~/.local/state/alloy.
      ExecStart = "${pkgs.grafana-alloy}/bin/alloy run --stability.level=public-preview --storage.path=%S/alloy --disable-reporting ${alloyConfig}";
      StateDirectory = "alloy";
      Restart = "on-failure";
      MemoryMax = "256M";
      # The archive holds prompts and tool output.
      UMask = "0077";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
