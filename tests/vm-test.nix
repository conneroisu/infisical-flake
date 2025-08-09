{ self, backend, frontend, pkgs, lib, ... }:

pkgs.nixosTest {
  name = "infisical-vm-test";
  
  nodes = {
    server = { config, pkgs, ... }: {
      imports = [ self.nixosModules.infisical ];
      
      # Enable PostgreSQL
      services.postgresql = {
        enable = true;
        ensureDatabases = [ "infisical" ];
        ensureUsers = [
          {
            name = "infisical";
            ensureDBOwnership = true;
          }
        ];
        authentication = ''
          host infisical infisical 127.0.0.1/32 md5
          host infisical infisical ::1/128 md5
        '';
        initialScript = pkgs.writeText "init.sql" ''
          ALTER USER infisical WITH PASSWORD 'infisical';
        '';
      };
      
      # Enable Redis
      services.redis.servers."infisical" = {
        enable = true;
        port = 6379;
      };
      
      # Configure Infisical
      services.infisical = {
        enable = true;
        package = backend;
        port = 8080;
        siteUrl = "http://localhost:8080";
        
        # WARNING: These are test-only keys, never use in production!
        encryptionKey = "6c1fe4e407b8911c104518103505b218";
        authSecret = "5lrMXKKWCVocS/uerPsl7V+TX/aaUaI7iDkgl3tSmLE=";
        
        database = {
          connectionUri = "postgres://infisical:infisical@localhost:5432/infisical";
          autoMigrate = true;
        };
        
        redis = {
          url = "redis://localhost:6379";
        };
        
        openFirewall = true;
      };
      
      # Nginx reverse proxy (optional)
      services.nginx = {
        enable = true;
        virtualHosts."infisical.local" = {
          locations."/" = {
            proxyPass = "http://localhost:8080";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
          };
        };
      };
      
      networking.firewall.allowedTCPPorts = [ 80 443 ];
      
      environment.systemPackages = with pkgs; [
        curl
        jq
        postgresql
      ];
    };
    
    client = { config, pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        curl
        jq
      ];
    };
  };
  
  testScript = ''
    import json
    
    start_all()
    
    # Wait for services to start
    server.wait_for_unit("postgresql.service")
    server.wait_for_unit("redis-infisical.service")
    server.wait_for_unit("infisical.service")
    server.wait_for_unit("nginx.service")
    
    # Wait for Infisical to be ready
    server.wait_for_open_port(8080)
    server.wait_for_open_port(80)
    
    # Test that Infisical is responding
    server.succeed("curl -f http://localhost:8080/api/status")
    
    # Test database connectivity
    server.succeed("sudo -u postgres psql -d infisical -c 'SELECT 1'")
    
    # Test Redis connectivity
    server.succeed("redis-cli -p 6379 ping | grep PONG")
    
    # Test API endpoints
    with subtest("Test API health endpoint"):
        result = server.succeed("curl -s http://localhost:8080/api/status")
        status = json.loads(result)
        assert "date" in status, "Status response should contain date"
    
    # Test from client machine
    with subtest("Test remote access"):
        client.wait_for_unit("multi-user.target")
        client.succeed("curl -f http://server:8080/api/status")
    
    # Test authentication endpoint exists
    with subtest("Test auth endpoints"):
        server.succeed("curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/api/v1/auth/login | grep -E '(400|401|405)'")
    
    # Test that migrations ran successfully
    with subtest("Test database migrations"):
        tables = server.succeed("sudo -u postgres psql -d infisical -c \"SELECT tablename FROM pg_tables WHERE schemaname = 'public'\" -t")
        assert "users" in tables, "Users table should exist"
        assert "organizations" in tables, "Organizations table should exist"
    
    # Test nginx proxy
    with subtest("Test nginx reverse proxy"):
        server.succeed("curl -H 'Host: infisical.local' http://localhost/api/status")
    
    print("All tests passed!")
  '';
}