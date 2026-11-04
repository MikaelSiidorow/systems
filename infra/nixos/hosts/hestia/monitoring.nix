{ pkgs, ... }:
{
  # Ships host metrics and the journal over OTLP to the cluster Alloy on
  # k8s-server (tailnet only), so a freeze is visible from outside the host.
  # Local agents send OTLP to 127.0.0.1:4318 and share the same disk queue.
  services.alloy.enable = true;

  # otelcol.storage.file is public preview.
  services.alloy.extraFlags = [ "--stability.level=public-preview" ];

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

    otelcol.receiver.otlp "agents" {
      http {
        endpoint = "127.0.0.1:4318"
      }

      output {
        metrics = [otelcol.processor.batch.default.input]
        logs    = [otelcol.processor.batch.default.input]
        traces  = [otelcol.processor.batch.default.input]
      }
    }

    otelcol.processor.batch "default" {
      output {
        metrics = [otelcol.exporter.otlphttp.cluster.input]
        logs    = [otelcol.exporter.otlphttp.cluster.input]
        traces  = [otelcol.exporter.otlphttp.cluster.input]
      }
    }

    // Lives under /var/lib/alloy/data-alloy; compaction gives the disk back
    // once a backlog drains.
    otelcol.storage.file "queue" {
      compaction {
        on_start   = true
        on_rebound = true
      }
    }

    // WireGuard encrypts the tailnet hop. During a cluster or tailnet outage
    // batches wait on disk and retry for a day instead of being dropped after
    // the default 5 minutes. A day of 15 s scrapes alone is ~5800 batches.
    otelcol.exporter.otlphttp "cluster" {
      client {
        endpoint = "http://100.64.0.1:4318"
      }

      sending_queue {
        queue_size = 20000
        storage    = otelcol.storage.file.queue.handler
      }

      retry_on_failure {
        max_elapsed_time = "24h"
      }
    }
  '';

  # Monitoring must not add to the memory pressure it is there to report.
  systemd.services.alloy.serviceConfig.MemoryMax = "256M";

  # RAPL energy counters are root-only (CVE-2020-8694); let Alloy read them, so
  # the rapl collector reports CPU package power. Alloy re-serves them on
  # 127.0.0.1:12345 to any local user, at roughly 60 ms per sample, far coarser
  # than a Platypus-style attack needs.
  users.groups.rapl = { };
  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "rapl" ];
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:*", RUN+="${pkgs.coreutils}/bin/chgrp rapl /sys%p/energy_uj", RUN+="${pkgs.coreutils}/bin/chmod g+r /sys%p/energy_uj"
  '';
}
