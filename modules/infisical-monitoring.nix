{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.infisical-monitoring;
  
  # Prometheus exporter configuration
  exporterConfig = pkgs.writeText "exporter-config.yml" ''
    metrics:
      - name: infisical_api_requests_total
        help: Total number of API requests
        type: counter
        labels:
          - method
          - endpoint
          - status
      
      - name: infisical_api_request_duration_seconds
        help: API request duration in seconds
        type: histogram
        labels:
          - method
          - endpoint
      
      - name: infisical_secrets_total
        help: Total number of secrets
        type: gauge
        labels:
          - project
          - environment
      
      - name: infisical_users_total
        help: Total number of users
        type: gauge
        labels:
          - organization
      
      - name: infisical_database_connections
        help: Number of database connections
        type: gauge
        labels:
          - state
      
      - name: infisical_redis_connections
        help: Number of Redis connections
        type: gauge
      
      - name: infisical_authentication_attempts_total
        help: Total authentication attempts
        type: counter
        labels:
          - method
          - result
  '';
  
  # Grafana dashboard
  grafanaDashboard = pkgs.writeText "infisical-dashboard.json" (builtins.toJSON {
    dashboard = {
      title = "Infisical Monitoring";
      uid = "infisical-main";
      panels = [
        {
          title = "API Request Rate";
          type = "graph";
          targets = [{
            expr = "rate(infisical_api_requests_total[5m])";
          }];
        }
        {
          title = "API Response Time";
          type = "graph";
          targets = [{
            expr = "histogram_quantile(0.95, rate(infisical_api_request_duration_seconds_bucket[5m]))";
          }];
        }
        {
          title = "Active Users";
          type = "stat";
          targets = [{
            expr = "infisical_users_total";
          }];
        }
        {
          title = "Total Secrets";
          type = "stat";
          targets = [{
            expr = "sum(infisical_secrets_total)";
          }];
        }
        {
          title = "Database Connections";
          type = "graph";
          targets = [{
            expr = "infisical_database_connections";
          }];
        }
        {
          title = "Authentication Success Rate";
          type = "graph";
          targets = [{
            expr = "rate(infisical_authentication_attempts_total{result=\"success\"}[5m]) / rate(infisical_authentication_attempts_total[5m])";
          }];
        }
      ];
    };
  });

in {
  options.services.infisical-monitoring = {
    enable = mkEnableOption "Infisical monitoring with Prometheus and Grafana";
    
    prometheus = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Prometheus metrics collection";
      };
      
      port = mkOption {
        type = types.port;
        default = 9090;
        description = "Prometheus port";
      };
      
      scrapeInterval = mkOption {
        type = types.str;
        default = "15s";
        description = "Metrics scrape interval";
      };
      
      retention = mkOption {
        type = types.str;
        default = "30d";
        description = "Metrics retention period";
      };
    };
    
    grafana = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable Grafana dashboards";
      };
      
      port = mkOption {
        type = types.port;
        default = 3000;
        description = "Grafana port";
      };
      
      domain = mkOption {
        type = types.str;
        default = "grafana.local";
        description = "Grafana domain name";
      };
    };
    
    alerting = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable alerting";
      };
      
      rules = mkOption {
        type = types.listOf types.attrs;
        default = [];
        description = "Alert rules";
        example = [{
          alert = "HighErrorRate";
          expr = "rate(infisical_api_requests_total{status=~\"5..\"}[5m]) > 0.05";
          for = "5m";
          labels.severity = "critical";
          annotations = {
            summary = "High error rate detected";
            description = "Error rate is above 5% for 5 minutes";
          };
        }];
      };
      
      alertmanager = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Alertmanager";
        };
        
        port = mkOption {
          type = types.port;
          default = 9093;
          description = "Alertmanager port";
        };
        
        receivers = mkOption {
          type = types.listOf types.attrs;
          default = [];
          description = "Alert receivers configuration";
        };
      };
    };
    
    logging = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable centralized logging with Loki";
      };
      
      loki = {
        port = mkOption {
          type = types.port;
          default = 3100;
          description = "Loki port";
        };
        
        retention = mkOption {
          type = types.str;
          default = "168h";
          description = "Log retention period";
        };
      };
      
      promtail = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Promtail log collector";
        };
      };
    };
    
    tracing = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable distributed tracing with Jaeger";
      };
      
      jaeger = {
        port = mkOption {
          type = types.port;
          default = 16686;
          description = "Jaeger UI port";
        };
        
        collectorPort = mkOption {
          type = types.port;
          default = 14268;
          description = "Jaeger collector port";
        };
      };
    };
  };
  
  config = mkIf cfg.enable {
    # Configure Infisical for monitoring
    services.infisical.telemetry = {
      enabled = true;
      exportType = "prometheus";
    };
    
    services.infisical.extraEnvironment = {
      OTEL_EXPORT_OTLP_ENDPOINT = mkIf cfg.tracing.enable "http://localhost:${toString cfg.tracing.jaeger.collectorPort}";
      PROMETHEUS_METRICS_PORT = "9091";
    };
    
    # Prometheus configuration
    services.prometheus = mkIf cfg.prometheus.enable {
      enable = true;
      port = cfg.prometheus.port;
      retentionTime = cfg.prometheus.retention;
      
      globalConfig = {
        scrape_interval = cfg.prometheus.scrapeInterval;
        evaluation_interval = cfg.prometheus.scrapeInterval;
      };
      
      scrapeConfigs = [
        {
          job_name = "infisical";
          static_configs = [{
            targets = [ "localhost:9091" ];
          }];
        }
        {
          job_name = "postgres_exporter";
          static_configs = [{
            targets = [ "localhost:9187" ];
          }];
        }
        {
          job_name = "redis_exporter";
          static_configs = [{
            targets = [ "localhost:9121" ];
          }];
        }
        {
          job_name = "node_exporter";
          static_configs = [{
            targets = [ "localhost:9100" ];
          }];
        }
      ];
      
      rules = mkIf cfg.alerting.enable [
        (pkgs.writeText "infisical-alerts.yml" (builtins.toJSON {
          groups = [{
            name = "infisical";
            rules = cfg.alerting.rules ++ [
              {
                alert = "InfisicalDown";
                expr = "up{job=\"infisical\"} == 0";
                for = "5m";
                labels.severity = "critical";
                annotations = {
                  summary = "Infisical is down";
                  description = "Infisical has been down for more than 5 minutes";
                };
              }
              {
                alert = "HighMemoryUsage";
                expr = "process_resident_memory_bytes{job=\"infisical\"} > 2e9";
                for = "10m";
                labels.severity = "warning";
                annotations = {
                  summary = "High memory usage";
                  description = "Infisical is using more than 2GB of memory";
                };
              }
              {
                alert = "DatabaseConnectionPoolExhausted";
                expr = "infisical_database_connections{state=\"idle\"} == 0";
                for = "5m";
                labels.severity = "warning";
                annotations = {
                  summary = "Database connection pool exhausted";
                  description = "No idle database connections available";
                };
              }
            ];
          }];
        }))
      ];
    };
    
    # Grafana configuration
    services.grafana = mkIf cfg.grafana.enable {
      enable = true;
      settings = {
        server = {
          http_port = cfg.grafana.port;
          domain = cfg.grafana.domain;
        };
      };
      
      provision = {
        enable = true;
        
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:${toString cfg.prometheus.port}";
            isDefault = true;
          }
        ] ++ optional cfg.logging.enable {
          name = "Loki";
          type = "loki";
          url = "http://localhost:${toString cfg.logging.loki.port}";
        } ++ optional cfg.tracing.enable {
          name = "Jaeger";
          type = "jaeger";
          url = "http://localhost:${toString cfg.tracing.jaeger.port}";
        };
        
        dashboards.settings.providers = [{
          name = "Infisical";
          folder = "Infisical";
          type = "file";
          options.path = pkgs.runCommand "grafana-dashboards" {} ''
            mkdir -p $out
            cp ${grafanaDashboard} $out/infisical-dashboard.json
          '';
        }];
      };
    };
    
    # Alertmanager configuration
    services.prometheus.alertmanager = mkIf cfg.alerting.alertmanager.enable {
      enable = true;
      port = cfg.alerting.alertmanager.port;
      
      configuration = {
        global = {
          resolve_timeout = "5m";
        };
        
        route = {
          group_by = [ "alertname" "cluster" "service" ];
          group_wait = "10s";
          group_interval = "10s";
          repeat_interval = "1h";
          receiver = "default";
        };
        
        receivers = cfg.alerting.alertmanager.receivers ++ [{
          name = "default";
        }];
      };
    };
    
    # Loki configuration
    services.loki = mkIf cfg.logging.enable {
      enable = true;
      configuration = {
        auth_enabled = false;
        
        server = {
          http_listen_port = cfg.logging.loki.port;
        };
        
        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore.store = "inmemory";
              replication_factor = 1;
            };
          };
        };
        
        schema_config = {
          configs = [{
            from = "2024-01-01";
            store = "boltdb-shipper";
            object_store = "filesystem";
            schema = "v11";
            index = {
              prefix = "index_";
              period = "24h";
            };
          }];
        };
        
        storage_config = {
          boltdb_shipper = {
            active_index_directory = "/var/lib/loki/boltdb-shipper-active";
            cache_location = "/var/lib/loki/boltdb-shipper-cache";
            shared_store = "filesystem";
          };
          filesystem = {
            directory = "/var/lib/loki/chunks";
          };
        };
        
        limits_config = {
          retention_period = cfg.logging.loki.retention;
        };
      };
    };
    
    # Promtail configuration
    services.promtail = mkIf (cfg.logging.enable && cfg.logging.promtail.enable) {
      enable = true;
      configuration = {
        server = {
          http_listen_port = 9080;
        };
        
        clients = [{
          url = "http://localhost:${toString cfg.logging.loki.port}/loki/api/v1/push";
        }];
        
        scrape_configs = [{
          job_name = "system";
          static_configs = [{
            targets = [ "localhost" ];
            labels = {
              job = "systemlogs";
              __path__ = "/var/log/*.log";
            };
          }];
        }
        {
          job_name = "infisical";
          static_configs = [{
            targets = [ "localhost" ];
            labels = {
              job = "infisical";
              __path__ = "/var/log/infisical/*.log";
            };
          }];
        }];
      };
    };
    
    # Jaeger configuration
    services.jaeger = mkIf cfg.tracing.enable {
      enable = true;
    };
    
    # PostgreSQL exporter
    services.prometheus.exporters.postgres = mkIf cfg.prometheus.enable {
      enable = true;
      port = 9187;
      dataSourceName = "postgresql://infisical:infisical@localhost:5432/infisical?sslmode=disable";
    };
    
    # Redis exporter
    services.prometheus.exporters.redis = mkIf cfg.prometheus.enable {
      enable = true;
      port = 9121;
    };
    
    # Node exporter
    services.prometheus.exporters.node = mkIf cfg.prometheus.enable {
      enable = true;
      port = 9100;
    };
  };
}