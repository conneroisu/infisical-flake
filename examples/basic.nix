# Basic Infisical configuration example
{ config, pkgs, ... }:

{
  imports = [ 
    ../modules/infisical.nix 
  ];
  
  # PostgreSQL database
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    ensureDatabases = [ "infisical" ];
    ensureUsers = [{
      name = "infisical";
      ensureDBOwnership = true;
    }];
    authentication = ''
      host infisical infisical 127.0.0.1/32 md5
    '';
    initialScript = pkgs.writeText "init.sql" ''
      ALTER USER infisical WITH PASSWORD 'changeme';
    '';
  };
  
  # Redis cache
  services.redis.servers.infisical = {
    enable = true;
    port = 6379;
  };
  
  # Infisical service
  services.infisical = {
    enable = true;
    port = 8080;
    siteUrl = "http://localhost:8080";
    
    # IMPORTANT: Generate secure keys for production!
    # openssl rand -hex 16
    encryptionKey = "changeme_32_character_hex_string";
    
    # openssl rand -base64 32
    authSecret = "changeme_base64_encoded_secret_key";
    
    database = {
      connectionUri = "postgres://infisical:changeme@localhost:5432/infisical";
      autoMigrate = true;
    };
    
    redis = {
      url = "redis://localhost:6379";
    };
    
    openFirewall = true;
  };
}