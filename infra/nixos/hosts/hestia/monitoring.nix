{ ... }:
{
  # Ships host metrics and the journal over OTLP to the cluster Alloy on
  # k8s-server (tailnet only), so a freeze is visible from outside the host.
  services.alloy.enable = true;

  environment.etc."alloy/config.alloy".text = ''
    prometheus.exporter.unix "host" {
      enable_collectors = ["systemd"]

      // Restart counts catch a crash loop, which reads as mostly active.
      systemd {
        enable_restarts = true
      }
    }

    discovery.relabel "host" {
      targets = prometheus.exporter.unix.host.targets

      // Matches the cluster node exporter's job, so the stock node alerts and
      // dashboards cover hestia too.
      rule {
        target_label = "job"
        replacement  = "node-exporter"
      }

      rule {
        target_label = "instance"
        replacement  = "hestia"
      }
    }

    prometheus.scrape "host" {
      targets         = discovery.relabel.host.output
      scrape_interval = "15s"
      forward_to      = [otelcol.receiver.prometheus.default.receiver]
    }

    otelcol.receiver.prometheus "default" {
      output {
        metrics = [otelcol.processor.batch.default.input]
      }
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }

      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
    }

    loki.source.journal "default" {
      max_age       = "12h"
      relabel_rules = loki.relabel.journal.rules
      labels        = {job = "systemd-journal", instance = "hestia"}
      forward_to    = [otelcol.receiver.loki.default.receiver]
    }

    // Also hints the cluster's otelcol.exporter.loki to keep these labels.
    otelcol.receiver.loki "default" {
      output {
        logs = [otelcol.processor.batch.default.input]
      }
    }

    otelcol.processor.batch "default" {
      output {
        metrics = [otelcol.exporter.otlphttp.cluster.input]
        logs    = [otelcol.exporter.otlphttp.cluster.input]
      }
    }

    // WireGuard encrypts the tailnet hop.
    otelcol.exporter.otlphttp "cluster" {
      client {
        endpoint = "http://100.64.0.1:4318"
      }
    }
  '';

  # Monitoring must not add to the memory pressure it is there to report.
  systemd.services.alloy.serviceConfig.MemoryMax = "256M";
}
