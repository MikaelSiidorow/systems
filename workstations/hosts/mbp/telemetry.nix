# Local Alloy, Loki, Tempo, Prometheus and Grafana for agent telemetry. Work
# sessions stay on this Mac: every listener is on loopback, nothing exports
# anywhere else. Alloy repeats the cluster pipeline (k8s/apps/alloy.yaml), so
# labels and metric names match what the agent-traces skill expects.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  stateDir = "${config.xdg.stateHome}/agent-telemetry";
  yaml = (pkgs.formats.yaml { }).generate;
  # 3000 and the backends' defaults clash with dev servers; OTLP keeps 4318.
  ports = {
    grafana = 43000;
    loki = 43100;
    lokiGrpc = 43105;
    tempo = 43200;
    tempoGrpc = 43205;
    tempoOtlp = 43217;
    prometheus = 43090;
    alloy = 43345;
  };
  # Metadata only (no prompts, output or commands), so a quarter is cheap.
  # Only Prometheus can cap size; Loki and Tempo expire by age alone.
  retention = "2160h";
  # The agents' only way to Grafana: their sandboxes allow this socket, not
  # loopback, which would open every local port.
  grafanaSocket = "${stateDir}/grafana.sock";

  lokiConfig = yaml "loki.yaml" {
    auth_enabled = false;
    server = {
      http_listen_address = "127.0.0.1";
      http_listen_port = ports.loki;
      grpc_listen_address = "127.0.0.1";
      grpc_listen_port = ports.lokiGrpc;
    };
    common = {
      path_prefix = "${stateDir}/loki";
      replication_factor = 1;
      instance_addr = "127.0.0.1";
      ring.kvstore.store = "inmemory";
      storage.filesystem = {
        chunks_directory = "${stateDir}/loki/chunks";
        rules_directory = "${stateDir}/loki/rules";
      };
    };
    memberlist.bind_addr = [ "127.0.0.1" ];
    frontend.address = "127.0.0.1";
    schema_config.configs = [
      {
        from = "2026-01-01";
        store = "tsdb";
        object_store = "filesystem";
        schema = "v13";
        index = {
          prefix = "index_";
          period = "24h";
        };
      }
    ];
    compactor = {
      working_directory = "${stateDir}/loki/compactor";
      retention_enabled = true;
      delete_request_store = "filesystem";
    };
    limits_config = {
      retention_period = retention;
      # The delete API is unauthenticated: a web page could erase logs.
      deletion_mode = "disabled";
    };
    analytics.reporting_enabled = false;
  };

  tempoConfig = yaml "tempo.yaml" {
    server = {
      http_listen_address = "127.0.0.1";
      http_listen_port = ports.tempo;
      grpc_listen_address = "127.0.0.1";
      grpc_listen_port = ports.tempoGrpc;
    };
    distributor.receivers.otlp.protocols.grpc.endpoint = "127.0.0.1:${toString ports.tempoOtlp}";
    ingester.lifecycler = {
      address = "127.0.0.1";
      ring = {
        kvstore.store = "inmemory";
        replication_factor = 1;
      };
    };
    memberlist.bind_addr = [ "127.0.0.1" ];
    compactor.compaction.block_retention = retention;
    storage.trace = {
      backend = "local";
      local.path = "${stateDir}/tempo/blocks";
      wal.path = "${stateDir}/tempo/wal";
    };
    usage_report.reporting_enabled = false;
  };

  prometheusConfig = yaml "prometheus.yaml" { global = { }; };

  alloyConfig = pkgs.writeText "config.alloy" ''
    otelcol.receiver.otlp "agents" {
      http {
        endpoint = "127.0.0.1:4318"
      }

      output {
        metrics = [otelcol.processor.transform.codex_host.input]
        logs    = [otelcol.processor.attributes.content.input]
        traces  = [otelcol.processor.attributes.content.input]
      }
    }

    // Second lock behind the agent settings: prompts, commands and tool
    // output never reach the stores, even if a flag is set elsewhere.
    // Codex has no setting for tool arguments at all.
    otelcol.processor.attributes "content" {
      // Exact names only, so metadata like user_prompt_length stays.
      // error carries failure text, which can include command output.
      action {
        pattern = "^(prompt|prompt_text|user_prompt|response|body|tool_input|tool_parameters|arguments|output|full_command|error)$"
        action  = "delete"
      }

      output {
        logs   = [otelcol.exporter.loki.default.input]
        traces = [otelcol.processor.transform.status.input]
      }
    }

    otelcol.processor.transform "status" {
      error_mode = "ignore"
      trace_statements {
        context    = "span"
        statements = [
          `set(span.status.message, "") where span.status.message != ""`,
        ]
      }
      output {
        traces = [otelcol.exporter.otlp.tempo.input]
      }
    }

    otelcol.exporter.otlp "tempo" {
      client {
        endpoint = "127.0.0.1:${toString ports.tempoOtlp}"
        tls {
          insecure = true
        }
      }
    }

    otelcol.exporter.loki "default" {
      forward_to = [loki.write.default.receiver]
    }

    loki.write "default" {
      endpoint {
        url = "http://127.0.0.1:${toString ports.loki}/loki/api/v1/push"
      }
    }

    // Codex tags metrics with the host only as the resource attribute env,
    // which the Prometheus exporter drops. As on the cluster.
    otelcol.processor.transform "codex_host" {
      error_mode = "ignore"
      metric_statements {
        context    = "datapoint"
        statements = [
          `set(attributes["host.name"], resource.attributes["env"]) where IsMatch(resource.attributes["service.name"], "^codex")`,
        ]
      }
      output {
        metrics = [otelcol.processor.deltatocumulative.default.input]
      }
    }

    // Claude Code and Codex send delta sums and histograms, which the
    // Prometheus exporter drops. Idle streams expire after 5m.
    otelcol.processor.deltatocumulative "default" {
      max_streams = 10000
      output {
        metrics = [otelcol.exporter.prometheus.default.input]
      }
    }

    otelcol.exporter.prometheus "default" {
      forward_to = [prometheus.remote_write.default.receiver]
    }

    prometheus.remote_write "default" {
      endpoint {
        url = "http://127.0.0.1:${toString ports.prometheus}/api/v1/write"
      }
    }
  '';

  # Anonymous viewers only, with no login, so there is no admin password to
  # keep. Phone-home features (updates, news, plugins, signing keys) are off.
  grafanaIni = pkgs.writeText "grafana.ini" (
    lib.generators.toINI { } {
      server = {
        http_addr = "127.0.0.1";
        http_port = ports.grafana;
        # Rejects DNS-rebound hosts; q and the browser use 127.0.0.1.
        domain = "127.0.0.1";
        enforce_domain = true;
      };
      paths = {
        data = "${stateDir}/grafana";
        logs = "${stateDir}/grafana/log";
        plugins = "${stateDir}/grafana/plugins";
        provisioning = grafanaProvisioning;
      };
      "auth.anonymous" = {
        enabled = true;
        org_role = "Viewer";
      };
      auth.disable_login_form = true;
      "auth.basic".enabled = false;
      # Lets anonymous viewers use Explore.
      users.viewers_can_edit = true;
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
        check_for_plugin_updates = false;
      };
      news.news_feed_enabled = false;
      plugins = {
        preinstall_disabled = true;
        public_key_retrieval_disabled = true;
        plugin_admin_enabled = false;
      };
      snapshots.external_enabled = false;
      security.disable_gravatar = true;
    }
  );

  # UIDs match the cluster's, which the agent-traces skill queries by.
  grafanaProvisioning = pkgs.linkFarm "grafana-provisioning" {
    "datasources/agents.yaml" = yaml "agents.yaml" {
      apiVersion = 1;
      datasources = [
        {
          name = "Loki";
          type = "loki";
          uid = "loki";
          url = "http://127.0.0.1:${toString ports.loki}";
        }
        {
          name = "Tempo";
          type = "tempo";
          uid = "tempo";
          url = "http://127.0.0.1:${toString ports.tempo}";
        }
        {
          name = "Prometheus";
          type = "prometheus";
          uid = "prometheus";
          url = "http://127.0.0.1:${toString ports.prometheus}";
          isDefault = true;
        }
      ];
    };
  };

  services = {
    alloy = [
      (lib.getExe pkgs.grafana-alloy)
      "run"
      "--server.http.listen-addr=127.0.0.1:${toString ports.alloy}"
      "--storage.path=${stateDir}/alloy"
      "--disable-reporting"
      # deltatocumulative is experimental, as on the cluster.
      "--stability.level=experimental"
      "${alloyConfig}"
    ];
    loki = [
      (lib.getExe pkgs.grafana-loki)
      "-config.file=${lokiConfig}"
    ];
    tempo = [
      (lib.getExe' pkgs.tempo "tempo")
      "-config.file=${tempoConfig}"
    ];
    prometheus = [
      (lib.getExe pkgs.prometheus)
      "--config.file=${prometheusConfig}"
      "--storage.tsdb.path=${stateDir}/prometheus"
      "--storage.tsdb.retention.time=90d"
      "--storage.tsdb.retention.size=20GB"
      "--web.listen-address=127.0.0.1:${toString ports.prometheus}"
      "--web.enable-remote-write-receiver"
    ];
    grafana-socket = [
      (lib.getExe pkgs.socat)
      "UNIX-LISTEN:${grafanaSocket},fork,unlink-early,mode=600"
      "TCP:127.0.0.1:${toString ports.grafana}"
    ];
    grafana = [
      (lib.getExe' pkgs.grafana "grafana")
      "server"
      "--homepath=${pkgs.grafana}/share/grafana"
      "--config=${grafanaIni}"
    ];
  };
in
{
  agents.telemetry = {
    endpoint = "http://127.0.0.1:4318";
    host = "mbp";
    toolDetails = false;
    grafana = "http://127.0.0.1:${toString ports.grafana}";
    inherit grafanaSocket;
  };

  # launchd must be able to open the log paths before the services start.
  home.activation.agentTelemetryState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run install -d -m 700 ${
      lib.concatMapStringsSep " " (name: lib.escapeShellArg "${stateDir}/${name}") (
        [ "" ] ++ lib.attrNames services
      )
    }
  '';

  launchd.agents = lib.mapAttrs' (
    name: args:
    lib.nameValuePair "telemetry-${name}" {
      enable = true;
      config = {
        ProgramArguments = args;
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        ProcessType = "Background";
        Umask = 63; # 077
        WorkingDirectory = "${stateDir}/${name}";
        # Soft heap target; launchd has no hard memory limit.
        EnvironmentVariables.GOMEMLIMIT = "256MiB";
        StandardOutPath = "${stateDir}/${name}/stdout.log";
        StandardErrorPath = "${stateDir}/${name}/stderr.log";
      };
    }
  ) services;
}
