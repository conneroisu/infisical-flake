# Infisical Nix Flake

A comprehensive Nix flake for packaging and deploying [Infisical](https://infisical.com), an open-source secret management platform, on NixOS.

## Features

- ✅ Complete Nix packaging for Infisical backend and frontend
- ✅ NixOS module for easy deployment
- ✅ PostgreSQL and Redis integration
- ✅ Automated database migrations
- ✅ VM-based integration tests
- ✅ Security hardening via systemd
- ✅ SSO support (Google, GitHub, GitLab)
- ✅ SMTP configuration for email notifications
- ✅ OpenTelemetry support

## Quick Start

### Using the Flake

Add this flake to your NixOS configuration:

```nix
{
  inputs.infisical.url = "github:yourusername/infisical-flake";
  
  outputs = { self, nixpkgs, infisical, ... }: {
    nixosConfigurations.yourhost = nixpkgs.lib.nixosSystem {
      modules = [
        infisical.nixosModules.infisical
        {
          services.infisical = {
            enable = true;
            siteUrl = "https://secrets.example.com";
            
            # IMPORTANT: Generate secure keys for production!
            encryptionKey = "your-secure-encryption-key";
            authSecret = "your-secure-auth-secret";
            
            database.connectionUri = "postgres://infisical:password@localhost/infisical";
            redis.url = "redis://localhost:6379";
          };
        }
      ];
    };
  };
}
```

### Development Environment

```bash
# Enter development shell
nix develop

# Build the backend package
nix build

# Build the frontend package
nix build .#frontend

# Run VM tests
nix build .#checks.x86_64-linux.infisical-vm-test
```

## Configuration Options

### Basic Configuration

```nix
services.infisical = {
  enable = true;
  port = 8080;
  host = "0.0.0.0";
  siteUrl = "https://secrets.example.com";
  
  # Security keys (MUST be changed for production!)
  encryptionKey = "32-character-hex-string";
  authSecret = "base64-encoded-secret";
  
  # Database configuration
  database = {
    connectionUri = "postgres://user:pass@host:5432/infisical";
    autoMigrate = true;  # Run migrations on startup
  };
  
  # Redis configuration
  redis = {
    url = "redis://localhost:6379";
  };
  
  # Open firewall port
  openFirewall = true;
};
```

### SMTP Configuration

```nix
services.infisical.smtp = {
  host = "smtp.gmail.com";
  port = 587;
  fromAddress = "noreply@example.com";
  fromName = "Infisical";
  username = "your-email@example.com";
  password = "your-smtp-password";
};
```

### SSO Configuration

```nix
services.infisical.sso = {
  google = {
    clientId = "your-google-client-id";
    clientSecret = "your-google-client-secret";
  };
  github = {
    clientId = "your-github-client-id";
    clientSecret = "your-github-client-secret";
  };
  gitlab = {
    clientId = "your-gitlab-client-id";
    clientSecret = "your-gitlab-client-secret";
  };
};
```

### Telemetry

```nix
services.infisical.telemetry = {
  enabled = true;
  exportType = "prometheus";  # or "otlp"
};
```

## Complete Example

```nix
{ config, pkgs, ... }:

{
  imports = [ ./infisical-flake/modules/infisical.nix ];
  
  # PostgreSQL
  services.postgresql = {
    enable = true;
    ensureDatabases = [ "infisical" ];
    ensureUsers = [{
      name = "infisical";
      ensureDBOwnership = true;
    }];
  };
  
  # Redis
  services.redis.servers.infisical = {
    enable = true;
    port = 6379;
  };
  
  # Infisical
  services.infisical = {
    enable = true;
    siteUrl = "https://secrets.example.com";
    
    # Generate with: openssl rand -hex 16
    encryptionKey = "your-32-char-hex-key-here";
    
    # Generate with: openssl rand -base64 32
    authSecret = "your-base64-auth-secret-here";
    
    database.connectionUri = "postgres://infisical@localhost/infisical";
    redis.url = "redis://localhost:6379";
    
    smtp = {
      host = "smtp.example.com";
      port = 587;
      fromAddress = "infisical@example.com";
      fromName = "Infisical";
      username = "smtp-user";
      password = "smtp-password";
    };
    
    openFirewall = true;
  };
  
  # Nginx reverse proxy
  services.nginx = {
    enable = true;
    virtualHosts."secrets.example.com" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://localhost:8080";
        proxyWebsockets = true;
      };
    };
  };
}
```

## Security Considerations

1. **Encryption Keys**: Always generate secure encryption keys and auth secrets for production:
   ```bash
   # Generate encryption key
   openssl rand -hex 16
   
   # Generate auth secret
   openssl rand -base64 32
   ```

2. **Database Security**: Use strong passwords and restrict database access

3. **Network Security**: Use HTTPS in production with proper SSL certificates

4. **Systemd Hardening**: The module includes security hardening options by default

## Testing

Run the included VM tests to verify your configuration:

```bash
nix build .#checks.x86_64-linux.infisical-vm-test
```

The tests verify:
- Service startup
- Database connectivity and migrations
- Redis connectivity
- API endpoints
- Nginx reverse proxy

## Troubleshooting

### Service won't start
Check logs: `journalctl -u infisical -f`

### Database connection issues
Ensure PostgreSQL is running and the connection URI is correct

### Migration failures
Check migration logs: `journalctl -u infisical | grep migration`

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test your changes with VM tests
4. Submit a pull request

## License

This flake is MIT licensed. Infisical itself is also MIT licensed.

## Acknowledgments

- [Infisical](https://infisical.com) for the excellent secret management platform
- NixOS community for packaging best practices