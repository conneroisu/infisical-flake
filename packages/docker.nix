{ lib
, dockerTools
, buildEnv
, nodejs_20
, infisical-backend
, infisical-frontend
, bash
, coreutils
, curl
}:

dockerTools.buildImage {
  name = "infisical";
  tag = "latest";
  
  contents = buildEnv {
    name = "infisical-env";
    paths = [
      infisical-backend
      bash
      coreutils
      curl
      nodejs_20
    ];
    pathsToLink = [ "/bin" "/lib" "/share" ];
  };
  
  runAsRoot = ''
    #!${bash}/bin/bash
    # Create necessary directories
    mkdir -p /var/lib/infisical
    mkdir -p /var/log/infisical
    mkdir -p /etc/infisical
    
    # Create non-root user
    groupadd -r infisical
    useradd -r -g infisical -d /var/lib/infisical -s /bin/false infisical
    
    # Set permissions
    chown -R infisical:infisical /var/lib/infisical
    chown -R infisical:infisical /var/log/infisical
    chown -R infisical:infisical /etc/infisical
  '';
  
  config = {
    Cmd = [ "${infisical-backend}/bin/infisical-backend" ];
    
    User = "infisical";
    WorkingDir = "/var/lib/infisical";
    
    Env = [
      "NODE_ENV=production"
      "HOST=0.0.0.0"
      "PORT=8080"
    ];
    
    ExposedPorts = {
      "8080/tcp" = {};
    };
    
    Volumes = {
      "/var/lib/infisical" = {};
      "/var/log/infisical" = {};
      "/etc/infisical" = {};
    };
    
    Healthcheck = {
      Test = [ "CMD" "${curl}/bin/curl" "-f" "http://localhost:8080/api/status" ];
      Interval = "30s";
      Timeout = "3s";
      Retries = 3;
      StartPeriod = "40s";
    };
    
    Labels = {
      "org.opencontainers.image.source" = "https://github.com/Infisical/infisical";
      "org.opencontainers.image.description" = "Infisical - Open-source secret management platform";
      "org.opencontainers.image.licenses" = "MIT";
    };
  };
}