# Alloy components shared by the hosts that forward agent telemetry to the
# cluster (infra/nixos/hosts/hestia/monitoring.nix,
# workstations/hosts/tpad/telemetry.nix). The host's OTLP receiver sends every
# signal to otelcol.processor.batch.archive, and logs and traces bound for the
# cluster through otelcol.processor.filter.content (traces) and
# otelcol.processor.attributes.content (logs). Both end at the host's
# otelcol.processor.batch.default. Needs --stability.level=public-preview.
archiveDir: ''
  // Raw archive: every signal as the agents sent it, before the T3 filter and
  // content stripping, so it keeps prompts and tool output. Each file is a run
  // of records, a 4-byte big-endian length then a zstd frame holding one
  // OTLP/JSON export request. Files rotate at 100 MB and go after 90 days;
  // the backup counts cap the archive at about 19 GB in all. Batches of 10s
  // compress better and keep a slow disk from stalling the receiver.
  otelcol.processor.batch "archive" {
    timeout = "10s"

    output {
      metrics = [otelcol.exporter.file.archive_metrics.input]
      logs    = [otelcol.exporter.file.archive_logs.input]
      traces  = [otelcol.exporter.file.archive_traces.input]
    }
  }

  otelcol.exporter.file "archive_traces" {
    path        = "${archiveDir}/traces.otlp"
    compression = "zstd"

    rotation {
      max_megabytes = 100
      max_days      = 90
      max_backups   = 150
    }
  }

  otelcol.exporter.file "archive_logs" {
    path        = "${archiveDir}/logs.otlp"
    compression = "zstd"

    rotation {
      max_megabytes = 100
      max_days      = 90
      max_backups   = 20
    }
  }

  otelcol.exporter.file "archive_metrics" {
    path        = "${archiveDir}/metrics.otlp"
    compression = "zstd"

    rotation {
      max_megabytes = 100
      max_days      = 90
      max_backups   = 20
    }
  }

  // Content stays on the host: Grafana on the cluster is readable without a
  // login. Claude's tool output arrives as a tool.output span event; prompt
  // and response text as attributes. Commands, tool input and error text
  // (OTEL_LOG_TOOL_DETAILS) and Codex tool output still go to the cluster.
  otelcol.processor.filter "content" {
    error_mode = "ignore"

    traces {
      spanevent = [`name == "tool.output"`]
    }

    output {
      traces = [otelcol.processor.attributes.content.input]
    }
  }

  // Exact names only, so metadata like prompt_length stays.
  otelcol.processor.attributes "content" {
    action {
      pattern = "^(prompt|prompt_text|user_prompt|response)$"
      action  = "delete"
    }

    output {
      logs   = [otelcol.processor.batch.default.input]
      traces = [otelcol.processor.batch.default.input]
    }
  }
''
