{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.infisical;
  
  envFile = pkgs.writeText "infisical.env" ''
    NODE_ENV=production
    HOST=${cfg.host}
    PORT=${toString cfg.port}
    SITE_URL=${cfg.siteUrl}
    
    # Database
    DB_CONNECTION_URI=${cfg.database.connectionUri}
    
    # Redis
    REDIS_URL=${cfg.redis.url}
    
    # Security
    ENCRYPTION_KEY=${cfg.encryptionKey}
    AUTH_SECRET=${cfg.authSecret}
    
    # SMTP
    ${optionalString (cfg.smtp.host != null) "SMTP_HOST=${cfg.smtp.host}"}
    ${optionalString (cfg.smtp.port != null) "SMTP_PORT=${toString cfg.smtp.port}"}
    ${optionalString (cfg.smtp.fromAddress != null) "SMTP_FROM_ADDRESS=${cfg.smtp.fromAddress}"}
    ${optionalString (cfg.smtp.fromName != null) "SMTP_FROM_NAME=${cfg.smtp.fromName}"}
    ${optionalString (cfg.smtp.username != null) "SMTP_USERNAME=${cfg.smtp.username}"}
    ${optionalString (cfg.smtp.password != null) "SMTP_PASSWORD=${cfg.smtp.password}"}
    
    # SSO
    ${optionalString (cfg.sso.google.clientId != null) "CLIENT_ID_GOOGLE_LOGIN=${cfg.sso.google.clientId}"}
    ${optionalString (cfg.sso.google.clientSecret != null) "CLIENT_SECRET_GOOGLE_LOGIN=${cfg.sso.google.clientSecret}"}
    ${optionalString (cfg.sso.github.clientId != null) "CLIENT_ID_GITHUB_LOGIN=${cfg.sso.github.clientId}"}
    ${optionalString (cfg.sso.github.clientSecret != null) "CLIENT_SECRET_GITHUB_LOGIN=${cfg.sso.github.clientSecret}"}
    ${optionalString (cfg.sso.gitlab.clientId != null) "CLIENT_ID_GITLAB_LOGIN=${cfg.sso.gitlab.clientId}"}
    ${optionalString (cfg.sso.gitlab.clientSecret != null) "CLIENT_SECRET_GITLAB_LOGIN=${cfg.sso.gitlab.clientSecret}"}
    
    # Telemetry
    OTEL_TELEMETRY_COLLECTION_ENABLED=${if cfg.telemetry.enabled then "true" else "false"}
    ${optionalString (cfg.telemetry.exportType != null) "OTEL_EXPORT_TYPE=${cfg.telemetry.exportType}"}
    
    # Additional environment variables
    ${concatStringsSep "\n" (mapAttrsToList (name: value: "${name}=${toString value}") cfg.extraEnvironment)}
  '';

in {
  options.services.infisical = {
    enable = mkEnableOption "Infisical secret management platform";
    
    package = mkOption {
      type = types.package;
      default = pkgs.infisical-backend;
      defaultText = literalExpression "pkgs.infisical-backend";
      description = "Infisical backend package to use";
    };
    
    user = mkOption {
      type = types.str;
      default = "infisical";
      description = "User account under which Infisical runs";
    };
    
    group = mkOption {
      type = types.str;
      default = "infisical";
      description = "Group under which Infisical runs";
    };
    
    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host to bind to";
    };
    
    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Port to listen on";
    };
    
    siteUrl = mkOption {
      type = types.str;
      example = "https://secrets.example.com";
      description = "Public URL of the Infisical instance";
    };
    
    encryptionKey = mkOption {
      type = types.str;
      description = ''
        Encryption key for platform encryption/decryption operations.
        WARNING: This should be a secure random key in production!
      '';
    };
    
    authSecret = mkOption {
      type = types.str;
      description = ''
        Secret for signing JWT tokens.
        WARNING: This should be a secure random key in production!
      '';
    };
    
    database = {
      connectionUri = mkOption {
        type = types.str;
        default = "postgres://infisical:infisical@localhost:5432/infisical";
        description = "PostgreSQL connection URI";
      };
      
      autoMigrate = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically run database migrations on startup";
      };
    };
    
    redis = {
      url = mkOption {
        type = types.str;
        default = "redis://localhost:6379";
        description = "Redis connection URL";
      };
    };
    
    smtp = {
      host = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SMTP server host";
      };
      
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "SMTP server port";
      };
      
      fromAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "From email address";
      };
      
      fromName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "From name";
      };
      
      username = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SMTP username";
      };
      
      password = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SMTP password";
      };
    };
    
    sso = {
      google = {
        clientId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Google OAuth client ID";
        };
        
        clientSecret = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Google OAuth client secret";
        };
      };
      
      github = {
        clientId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "GitHub OAuth client ID";
        };
        
        clientSecret = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "GitHub OAuth client secret";
        };
      };
      
      gitlab = {
        clientId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "GitLab OAuth client ID";
        };
        
        clientSecret = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "GitLab OAuth client secret";
        };
      };
    };
    
    telemetry = {
      enabled = mkOption {
        type = types.bool;
        default = false;
        description = "Enable OpenTelemetry collection";
      };
      
      exportType = mkOption {
        type = types.nullOr (types.enum [ "prometheus" "otlp" ]);
        default = null;
        description = "Telemetry export type";
      };
    };
    
    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Additional environment variables";
    };
    
    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the firewall for the Infisical port";
    };
  };
  
  config = mkIf cfg.enable {
    # Create user and group
    users.users = mkIf (cfg.user == "infisical") {
      infisical = {
        group = cfg.group;
        isSystemUser = true;
        description = "Infisical service user";
      };
    };
    
    users.groups = mkIf (cfg.group == "infisical") {
      infisical = {};
    };
    
    # Systemd service
    systemd.services.infisical = {
      description = "Infisical Secret Management Platform";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "redis.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        ExecStartPre = mkIf cfg.database.autoMigrate "${cfg.package}/bin/infisical-migrate";
        ExecStart = "${cfg.package}/bin/infisical-backend";
        EnvironmentFile = envFile;
        Restart = "always";
        RestartSec = 10;
        
        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/infisical" ];
        StateDirectory = "infisical";
        WorkingDirectory = "/var/lib/infisical";
        
        # Resource limits
        LimitNOFILE = 65536;
      };
    };
    
    # Open firewall if requested
    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
    
    # Warnings for insecure defaults
    warnings = []
      ++ optional (cfg.encryptionKey == "6c1fe4e407b8911c104518103505b218") 
        "services.infisical.encryptionKey is using the insecure default value. Please generate a secure key for production!"
      ++ optional (cfg.authSecret == "5lrMXKKWCVocS/uerPsl7V+TX/aaUaI7iDkgl3tSmLE=")
        "services.infisical.authSecret is using the insecure default value. Please generate a secure key for production!";
  };
}