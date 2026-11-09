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
        metrics = [otelcol.processor.deltatocumulative.default.input]
        logs    = [otelcol.exporter.loki.default.input]
        traces  = [otelcol.exporter.otlp.tempo.input]
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
    grafana = [
      (lib.getExe' pkgs.grafana "grafana")
      "server"
      "--homepath=${pkgs.grafana}/share/grafana"
      "--config=${grafanaIni}"
    ];
  };
in
{
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
