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
  // OTLP/JSON export request. Files rotate by size only, and rotated files
  // go after 90 days or past the backup count, which caps the archive at
  // about 16 GB in all; a quiet file can hold older data until it rotates.
  // Batches of 10s compress better. A write error drops the archive batch
  // only, but a hung disk stalls the receiver once the batch queue fills.
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

    // Small, so prompts rotate and expire sooner.
    rotation {
      max_megabytes = 10
      max_days      = 90
      max_backups   = 20
    }
  }

  otelcol.exporter.file "archive_metrics" {
    path        = "${archiveDir}/metrics.otlp"
    compression = "zstd"

    rotation {
      max_megabytes = 10
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

  // Exact names only, so metadata like prompt_length stays. Beyond the
  // content settings, this covers Claude's detailed beta tracing and raw API
  // bodies, should a shell turn them on.
  otelcol.processor.attributes "content" {
    action {
      pattern = "^(prompt|prompt_text|user_prompt|response|response\\.model_output|body|system_prompt|system_prompt_preview|user_system_prompt|new_context|system_reminders)$"
      action  = "delete"
    }

    output {
      logs   = [otelcol.processor.batch.default.input]
      traces = [otelcol.processor.batch.default.input]
    }
  }
''
