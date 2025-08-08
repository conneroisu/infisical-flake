{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.infisical-cluster;
  
  # Generate cluster configuration
  clusterConfig = pkgs.writeText "cluster-config.json" (builtins.toJSON {
    cluster = {
      enabled = true;
      nodeId = cfg.nodeId;
      nodes = cfg.nodes;
      replication = cfg.replication;
      loadBalancing = cfg.loadBalancing;
    };
  });

in {
  options.services.infisical-cluster = {
    enable = mkEnableOption "Infisical clustering for high availability";
    
    nodeId = mkOption {
      type = types.str;
      example = "node-1";
      description = "Unique identifier for this cluster node";
    };
    
    nodes = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [ "192.168.1.10:8080" "192.168.1.11:8080" "192.168.1.12:8080" ];
      description = "List of cluster node addresses";
    };
    
    replication = {
      enabled = mkOption {
        type = types.bool;
        default = true;
        description = "Enable data replication across nodes";
      };
      
      factor = mkOption {
        type = types.int;
        default = 3;
        description = "Replication factor for data redundancy";
      };
      
      consistency = mkOption {
        type = types.enum [ "eventual" "strong" "quorum" ];
        default = "quorum";
        description = "Consistency level for replicated data";
      };
    };
    
    loadBalancing = {
      enabled = mkOption {
        type = types.bool;
        default = true;
        description = "Enable load balancing across cluster nodes";
      };
      
      algorithm = mkOption {
        type = types.enum [ "round-robin" "least-connections" "ip-hash" "consistent-hash" ];
        default = "least-connections";
        description = "Load balancing algorithm";
      };
      
      healthCheck = {
        enabled = mkOption {
          type = types.bool;
          default = true;
          description = "Enable health checking for cluster nodes";
        };
        
        interval = mkOption {
          type = types.int;
          default = 5;
          description = "Health check interval in seconds";
        };
        
        timeout = mkOption {
          type = types.int;
          default = 3;
          description = "Health check timeout in seconds";
        };
        
        unhealthyThreshold = mkOption {
          type = types.int;
          default = 3;
          description = "Number of failed checks before marking node unhealthy";
        };
      };
    };
    
    failover = {
      automatic = mkOption {
        type = types.bool;
        default = true;
        description = "Enable automatic failover on node failure";
      };
      
      timeout = mkOption {
        type = types.int;
        default = 30;
        description = "Failover timeout in seconds";
      };
      
      strategy = mkOption {
        type = types.enum [ "active-passive" "active-active" ];
        default = "active-active";
        description = "Failover strategy";
      };
    };
    
    synchronization = {
      interval = mkOption {
        type = types.int;
        default = 10;
        description = "State synchronization interval in seconds";
      };
      
      batchSize = mkOption {
        type = types.int;
        default = 100;
        description = "Maximum batch size for sync operations";
      };
    };
  };
  
  config = mkIf cfg.enable {
    # Ensure base Infisical service is configured
    services.infisical = {
      extraEnvironment = {
        CLUSTER_ENABLED = "true";
        CLUSTER_NODE_ID = cfg.nodeId;
        CLUSTER_NODES = concatStringsSep "," cfg.nodes;
        CLUSTER_CONFIG_PATH = "${clusterConfig}";
        REPLICATION_FACTOR = toString cfg.replication.factor;
        CONSISTENCY_LEVEL = cfg.replication.consistency;
        LOAD_BALANCING_ALGORITHM = cfg.loadBalancing.algorithm;
      };
    };
    
    # HAProxy for load balancing
    services.haproxy = mkIf cfg.loadBalancing.enabled {
      enable = true;
      config = ''
        global
          daemon
          maxconn 4096
          
        defaults
          mode http
          timeout connect 5000ms
          timeout client 50000ms
          timeout server 50000ms
          
        frontend infisical_frontend
          bind *:80
          default_backend infisical_backend
          
        backend infisical_backend
          balance ${cfg.loadBalancing.algorithm}
          option httpchk GET /api/status
          ${concatMapStringsSep "\n" (node: 
            let 
              parts = splitString ":" node;
              host = elemAt parts 0;
              port = elemAt parts 1;
            in "server ${host} ${node} check inter ${toString (cfg.loadBalancing.healthCheck.interval * 1000)}ms"
          ) cfg.nodes}
      '';
    };
    
    # Keepalived for high availability
    services.keepalived = mkIf cfg.failover.automatic {
      enable = true;
      vrrpInstances.infisical = {
        interface = "eth0";
        state = if cfg.nodeId == "node-1" then "MASTER" else "BACKUP";
        virtualRouterId = 51;
        priority = if cfg.nodeId == "node-1" then 100 else 50;
        virtualIps = [ "192.168.1.100/24" ];
        trackScripts = [ "check_infisical" ];
      };
      
      vrrpScripts = {
        check_infisical = {
          script = "${pkgs.curl}/bin/curl -f http://localhost:8080/api/status";
          interval = cfg.loadBalancing.healthCheck.interval;
          timeout = cfg.loadBalancing.healthCheck.timeout;
          rise = 2;
          fall = cfg.loadBalancing.healthCheck.unhealthyThreshold;
        };
      };
    };
    
    # Cluster synchronization service
    systemd.services.infisical-cluster-sync = {
      description = "Infisical Cluster Synchronization";
      wantedBy = [ "multi-user.target" ];
      after = [ "infisical.service" ];
      
      serviceConfig = {
        Type = "simple";
        ExecStart = pkgs.writeScript "cluster-sync.sh" ''
          #!${pkgs.bash}/bin/bash
          while true; do
            # Sync cluster state
            for node in ${concatStringsSep " " cfg.nodes}; do
              if [ "$node" != "${cfg.nodeId}" ]; then
                ${pkgs.curl}/bin/curl -X POST \
                  -H "Content-Type: application/json" \
                  -d '{"nodeId":"${cfg.nodeId}","timestamp":"$(date -Iseconds)"}' \
                  "http://$node/api/cluster/sync" || true
              fi
            done
            sleep ${toString cfg.synchronization.interval}
          done
        '';
        Restart = "always";
        RestartSec = 10;
      };
    };
    
    # Firewall rules for cluster communication
    networking.firewall = {
      allowedTCPPorts = [ 
        8080  # Infisical API
        5555  # Cluster communication
        2224  # Keepalived
      ];
      
      extraCommands = ''
        # Allow VRRP protocol for Keepalived
        iptables -A INPUT -p vrrp -j ACCEPT
        iptables -A OUTPUT -p vrrp -j ACCEPT
        
        # Allow cluster nodes to communicate
        ${concatMapStringsSep "\n" (node:
          let host = head (splitString ":" node);
          in ''
            iptables -A INPUT -s ${host} -j ACCEPT
            iptables -A OUTPUT -d ${host} -j ACCEPT
          ''
        ) cfg.nodes}
      '';
    };
  };
}