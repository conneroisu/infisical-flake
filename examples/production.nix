# Production Infisical configuration with clustering, monitoring, and backups
{ config, pkgs, ... }:

{
  imports = [ 
    ../modules/infisical.nix
    ../modules/infisical-cluster.nix
    ../modules/infisical-monitoring.nix
    ../modules/infisical-backup.nix
  ];
  
  # PostgreSQL with replication
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    
    ensureDatabases = [ "infisical" ];
    ensureUsers = [{
      name = "infisical";
      ensureDBOwnership = true;
    }];
    
    settings = {
      max_connections = 200;
      shared_buffers = "256MB";
      effective_cache_size = "1GB";
      maintenance_work_mem = "64MB";
      checkpoint_completion_target = 0.9;
      wal_buffers = "16MB";
      default_statistics_target = 100;
      random_page_cost = 1.1;
      effective_io_concurrency = 200;
      work_mem = "4MB";
      min_wal_size = "1GB";
      max_wal_size = "4GB";
    };
    
    authentication = ''
      host infisical infisical 127.0.0.1/32 md5
      host infisical infisical ::1/128 md5
    '';
  };
  
  # Redis with persistence
  services.redis.servers.infisical = {
    enable = true;
    port = 6379;
    save = [
      "900 1"    # after 900 sec (15 min) if at least 1 key changed
      "300 10"   # after 300 sec (5 min) if at least 10 keys changed
      "60 10000" # after 60 sec if at least 10000 keys changed
    ];
    appendOnly = true;
    appendFsync = "everysec";
  };
  
  # Infisical service
  services.infisical = {
    enable = true;
    port = 8080;
    siteUrl = "https://secrets.example.com";
    
    # Use proper secrets management in production
    encryptionKey = builtins.readFile /run/secrets/infisical-encryption-key;
    authSecret = builtins.readFile /run/secrets/infisical-auth-secret;
    
    database = {
      connectionUri = "postgres://infisical:${builtins.readFile /run/secrets/db-password}@localhost:5432/infisical?sslmode=require";
      autoMigrate = true;
    };
    
    redis = {
      url = "redis://localhost:6379";
    };
    
    # Email configuration
    smtp = {
      host = "smtp.example.com";
      port = 587;
      fromAddress = "noreply@example.com";
      fromName = "Infisical";
      username = "smtp-user";
      password = builtins.readFile /run/secrets/smtp-password;
    };
    
    # SSO configuration
    sso = {
      google = {
        clientId = builtins.readFile /run/secrets/google-client-id;
        clientSecret = builtins.readFile /run/secrets/google-client-secret;
      };
      github = {
        clientId = builtins.readFile /run/secrets/github-client-id;
        clientSecret = builtins.readFile /run/secrets/github-client-secret;
      };
    };
    
    # Enable telemetry
    telemetry = {
      enabled = true;
      exportType = "prometheus";
    };
    
    extraEnvironment = {
      # Performance tuning
      NODE_OPTIONS = "--max-old-space-size=4096";
      UV_THREADPOOL_SIZE = "128";
      
      # Security headers
      SECURE_HEADERS_ENABLED = "true";
      HSTS_MAX_AGE = "31536000";
      CSP_ENABLED = "true";
    };
  };
  
  # Clustering configuration
  services.infisical-cluster = {
    enable = true;
    nodeId = "node-1";
    nodes = [
      "192.168.1.10:8080"
      "192.168.1.11:8080"
      "192.168.1.12:8080"
    ];
    
    replication = {
      enabled = true;
      factor = 3;
      consistency = "quorum";
    };
    
    loadBalancing = {
      enabled = true;
      algorithm = "least-connections";
      healthCheck = {
        enabled = true;
        interval = 5;
        timeout = 3;
        unhealthyThreshold = 3;
      };
    };
    
    failover = {
      automatic = true;
      timeout = 30;
      strategy = "active-active";
    };
  };
  
  # Monitoring configuration
  services.infisical-monitoring = {
    enable = true;
    
    prometheus = {
      enable = true;
      port = 9090;
      scrapeInterval = "15s";
      retention = "90d";
    };
    
    grafana = {
      enable = true;
      port = 3000;
      domain = "monitoring.example.com";
    };
    
    alerting = {
      enable = true;
      rules = [
        {
          alert = "HighErrorRate";
          expr = "rate(infisical_api_requests_total{status=~\"5..\"}[5m]) > 0.05";
          for = "5m";
          labels.severity = "critical";
          annotations = {
            summary = "High error rate detected";
            description = "Error rate is above 5% for 5 minutes";
          };
        }
        {
          alert = "LowDiskSpace";
          expr = "node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"} < 0.1";
          for = "5m";
          labels.severity = "warning";
          annotations = {
            summary = "Low disk space";
            description = "Less than 10% disk space remaining";
          };
        }
      ];
      
      alertmanager = {
        enable = true;
        receivers = [
          {
            name = "email";
            email_configs = [{
              to = "ops@example.com";
              from = "alertmanager@example.com";
              smarthost = "smtp.example.com:587";
              auth_username = "alertmanager";
              auth_password = builtins.readFile /run/secrets/alertmanager-smtp-password;
            }];
          }
          {
            name = "slack";
            slack_configs = [{
              api_url = builtins.readFile /run/secrets/slack-webhook-url;
              channel = "#alerts";
            }];
          }
        ];
      };
    };
    
    logging = {
      enable = true;
      loki = {
        port = 3100;
        retention = "720h"; # 30 days
      };
      promtail.enable = true;
    };
    
    tracing = {
      enable = true;
      jaeger = {
        port = 16686;
        collectorPort = 14268;
      };
    };
  };
  
  # Backup configuration
  services.infisical-backup = {
    enable = true;
    backupPath = "/var/backup/infisical";
    schedule = "00:00:00"; # Daily at midnight
    
    database = {
      enable = true;
      password = builtins.readFile /run/secrets/db-password;
    };
    
    redis.enable = true;
    configuration.enable = true;
    
    compression.enable = true;
    
    encryption = {
      enable = true;
      passphrase = builtins.readFile /run/secrets/backup-encryption-key;
    };
    
    retention.days = 30;
    
    remote = {
      type = "s3";
      s3 = {
        bucket = "infisical-backups";
        prefix = "production";
        region = "us-east-1";
      };
    };
  };
  
  # Nginx reverse proxy with SSL
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    
    virtualHosts = {
      "secrets.example.com" = {
        enableACME = true;
        forceSSL = true;
        
        locations."/" = {
          proxyPass = "http://localhost:8080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            # Security headers
            add_header X-Frame-Options "SAMEORIGIN" always;
            add_header X-Content-Type-Options "nosniff" always;
            add_header X-XSS-Protection "1; mode=block" always;
            add_header Referrer-Policy "strict-origin-when-cross-origin" always;
            add_header Content-Security-Policy "default-src 'self' https:; script-src 'self' 'unsafe-inline' 'unsafe-eval' https:; style-src 'self' 'unsafe-inline' https:;" always;
            
            # Rate limiting
            limit_req zone=api burst=20 nodelay;
          '';
        };
      };
      
      "monitoring.example.com" = {
        enableACME = true;
        forceSSL = true;
        locations."/" = {
          proxyPass = "http://localhost:3000";
        };
      };
    };
    
    appendHttpConfig = ''
      # Rate limiting zones
      limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
      limit_req_status 429;
      
      # Connection limits
      limit_conn_zone $binary_remote_addr zone=addr:10m;
      limit_conn addr 100;
    '';
  };
  
  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 80 443 ];
  };
  
  # System monitoring
  services.netdata = {
    enable = true;
    config = {
      global = {
        "update every" = 1;
        "history" = 3600;
      };
    };
  };
  
  # Automatic security updates
  system.autoUpgrade = {
    enable = true;
    allowReboot = false;
    dates = "04:00";
  };
  
  # Security hardening
  security = {
    sudo.wheelNeedsPassword = true;
    
    auditd.enable = true;
    audit.enable = true;
    
    apparmor.enable = true;
  };
}