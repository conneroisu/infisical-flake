{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.infisical-backup;
  
  backupScript = pkgs.writeScript "infisical-backup.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    
    BACKUP_DIR="${cfg.backupPath}"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_NAME="infisical_backup_$TIMESTAMP"
    
    echo "Starting Infisical backup: $BACKUP_NAME"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR/$BACKUP_NAME"
    
    # Backup PostgreSQL database
    ${optionalString cfg.database.enable ''
      echo "Backing up PostgreSQL database..."
      PGPASSWORD="${cfg.database.password}" ${pkgs.postgresql}/bin/pg_dump \
        -h ${cfg.database.host} \
        -p ${toString cfg.database.port} \
        -U ${cfg.database.username} \
        -d ${cfg.database.database} \
        --format=custom \
        --file="$BACKUP_DIR/$BACKUP_NAME/database.dump"
    ''}
    
    # Backup Redis data
    ${optionalString cfg.redis.enable ''
      echo "Backing up Redis data..."
      ${pkgs.redis}/bin/redis-cli \
        -h ${cfg.redis.host} \
        -p ${toString cfg.redis.port} \
        --rdb "$BACKUP_DIR/$BACKUP_NAME/redis.rdb"
    ''}
    
    # Backup configuration files
    ${optionalString cfg.configuration.enable ''
      echo "Backing up configuration files..."
      mkdir -p "$BACKUP_DIR/$BACKUP_NAME/config"
      cp -r /var/lib/infisical/* "$BACKUP_DIR/$BACKUP_NAME/config/" 2>/dev/null || true
    ''}
    
    # Compress backup
    ${optionalString cfg.compression.enable ''
      echo "Compressing backup..."
      cd "$BACKUP_DIR"
      ${pkgs.gzip}/bin/tar -czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
      rm -rf "$BACKUP_NAME"
    ''}
    
    # Encrypt backup
    ${optionalString cfg.encryption.enable ''
      echo "Encrypting backup..."
      ${pkgs.gnupg}/bin/gpg \
        --cipher-algo AES256 \
        --symmetric \
        --batch \
        --passphrase "${cfg.encryption.passphrase}" \
        "$BACKUP_DIR/$BACKUP_NAME.tar.gz"
      rm "$BACKUP_DIR/$BACKUP_NAME.tar.gz"
    ''}
    
    # Upload to remote storage
    ${optionalString (cfg.remote.type != null) (
      if cfg.remote.type == "s3" then ''
        echo "Uploading to S3..."
        ${pkgs.awscli2}/bin/aws s3 cp \
          "$BACKUP_DIR/$BACKUP_NAME.tar.gz${optionalString cfg.encryption.enable ".gpg"}" \
          "s3://${cfg.remote.s3.bucket}/${cfg.remote.s3.prefix}/"
      '' else if cfg.remote.type == "rsync" then ''
        echo "Syncing to remote server..."
        ${pkgs.rsync}/bin/rsync -avz \
          "$BACKUP_DIR/$BACKUP_NAME.tar.gz${optionalString cfg.encryption.enable ".gpg"}" \
          "${cfg.remote.rsync.destination}"
      '' else ""
    )}
    
    # Cleanup old backups
    ${optionalString (cfg.retention.days > 0) ''
      echo "Cleaning up old backups..."
      find "$BACKUP_DIR" -name "infisical_backup_*.tar.gz*" -mtime +${toString cfg.retention.days} -delete
    ''}
    
    echo "Backup completed: $BACKUP_NAME"
  '';
  
  restoreScript = pkgs.writeScript "infisical-restore.sh" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    
    BACKUP_FILE="$1"
    
    if [ -z "$BACKUP_FILE" ]; then
      echo "Usage: $0 <backup_file>"
      exit 1
    fi
    
    echo "Starting Infisical restore from: $BACKUP_FILE"
    
    RESTORE_DIR=$(mktemp -d)
    
    # Decrypt if needed
    if [[ "$BACKUP_FILE" == *.gpg ]]; then
      echo "Decrypting backup..."
      ${pkgs.gnupg}/bin/gpg \
        --decrypt \
        --batch \
        --passphrase "${cfg.encryption.passphrase}" \
        "$BACKUP_FILE" > "$RESTORE_DIR/backup.tar.gz"
      BACKUP_FILE="$RESTORE_DIR/backup.tar.gz"
    fi
    
    # Extract backup
    echo "Extracting backup..."
    ${pkgs.gzip}/bin/tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"
    
    BACKUP_NAME=$(ls "$RESTORE_DIR" | grep infisical_backup | head -1)
    
    # Stop services
    echo "Stopping services..."
    systemctl stop infisical
    
    # Restore PostgreSQL database
    if [ -f "$RESTORE_DIR/$BACKUP_NAME/database.dump" ]; then
      echo "Restoring PostgreSQL database..."
      PGPASSWORD="${cfg.database.password}" ${pkgs.postgresql}/bin/pg_restore \
        -h ${cfg.database.host} \
        -p ${toString cfg.database.port} \
        -U ${cfg.database.username} \
        -d ${cfg.database.database} \
        --clean \
        --if-exists \
        "$RESTORE_DIR/$BACKUP_NAME/database.dump"
    fi
    
    # Restore Redis data
    if [ -f "$RESTORE_DIR/$BACKUP_NAME/redis.rdb" ]; then
      echo "Restoring Redis data..."
      systemctl stop redis-infisical
      cp "$RESTORE_DIR/$BACKUP_NAME/redis.rdb" /var/lib/redis/dump.rdb
      chown redis:redis /var/lib/redis/dump.rdb
      systemctl start redis-infisical
    fi
    
    # Restore configuration
    if [ -d "$RESTORE_DIR/$BACKUP_NAME/config" ]; then
      echo "Restoring configuration..."
      cp -r "$RESTORE_DIR/$BACKUP_NAME/config/"* /var/lib/infisical/
    fi
    
    # Start services
    echo "Starting services..."
    systemctl start infisical
    
    # Cleanup
    rm -rf "$RESTORE_DIR"
    
    echo "Restore completed successfully"
  '';

in {
  options.services.infisical-backup = {
    enable = mkEnableOption "Infisical backup service";
    
    backupPath = mkOption {
      type = types.path;
      default = "/var/backup/infisical";
      description = "Local path for storing backups";
    };
    
    schedule = mkOption {
      type = types.str;
      default = "daily";
      example = "00:00:00";
      description = "Backup schedule (systemd timer format)";
    };
    
    database = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Backup PostgreSQL database";
      };
      
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Database host";
      };
      
      port = mkOption {
        type = types.port;
        default = 5432;
        description = "Database port";
      };
      
      username = mkOption {
        type = types.str;
        default = "infisical";
        description = "Database username";
      };
      
      password = mkOption {
        type = types.str;
        default = "infisical";
        description = "Database password";
      };
      
      database = mkOption {
        type = types.str;
        default = "infisical";
        description = "Database name";
      };
    };
    
    redis = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Backup Redis data";
      };
      
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "Redis host";
      };
      
      port = mkOption {
        type = types.port;
        default = 6379;
        description = "Redis port";
      };
    };
    
    configuration = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Backup configuration files";
      };
    };
    
    compression = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable backup compression";
      };
    };
    
    encryption = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Enable backup encryption";
      };
      
      passphrase = mkOption {
        type = types.str;
        default = "";
        description = "Encryption passphrase";
      };
    };
    
    retention = {
      days = mkOption {
        type = types.int;
        default = 30;
        description = "Number of days to retain backups (0 = unlimited)";
      };
    };
    
    remote = {
      type = mkOption {
        type = types.nullOr (types.enum [ "s3" "rsync" ]);
        default = null;
        description = "Remote backup storage type";
      };
      
      s3 = {
        bucket = mkOption {
          type = types.str;
          default = "";
          description = "S3 bucket name";
        };
        
        prefix = mkOption {
          type = types.str;
          default = "infisical-backups";
          description = "S3 key prefix";
        };
        
        region = mkOption {
          type = types.str;
          default = "us-east-1";
          description = "AWS region";
        };
      };
      
      rsync = {
        destination = mkOption {
          type = types.str;
          default = "";
          example = "user@backup-server:/backups/infisical";
          description = "Rsync destination";
        };
      };
    };
  };
  
  config = mkIf cfg.enable {
    # Create backup directory
    systemd.tmpfiles.rules = [
      "d ${cfg.backupPath} 0700 root root -"
    ];
    
    # Backup service
    systemd.services.infisical-backup = {
      description = "Infisical Backup Service";
      after = [ "infisical.service" ];
      
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupScript}";
        User = "root";
        Group = "root";
        PrivateTmp = true;
      };
    };
    
    # Backup timer
    systemd.timers.infisical-backup = {
      description = "Infisical Backup Timer";
      wantedBy = [ "timers.target" ];
      
      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
      };
    };
    
    # Install restore script
    environment.systemPackages = [
      (pkgs.writeScriptBin "infisical-restore" restoreScript)
    ];
  };
}