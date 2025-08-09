{
  description = "Infisical - Open-source secret management platform with NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix, ... }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      version = "latest";
      
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          
          infisical-backend = pkgs.callPackage ./packages/backend.nix {
            inherit version;
          };
          
          infisical-frontend = pkgs.callPackage ./packages/frontend.nix {
            inherit version;
          };
          
          infisical-docker = pkgs.callPackage ./packages/docker.nix {
            inherit infisical-backend infisical-frontend;
          };
        in
        {
          default = infisical-backend;
          backend = infisical-backend;
          frontend = infisical-frontend;
          docker = infisical-docker;
        });

      nixosModules = {
        default = self.nixosModules.infisical;
        infisical = ./modules/infisical.nix;
        infisical-cluster = ./modules/infisical-cluster.nix;
        infisical-backup = ./modules/infisical-backup.nix;
        infisical-monitoring = ./modules/infisical-monitoring.nix;
      };

      checks = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          infisical-vm-test = pkgs.callPackage ./tests/vm-test.nix {
            inherit self;
            inherit (self.packages.${system}) backend frontend;
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            name = "infisical-dev";
            packages = with pkgs; [
              nodejs_20
              nodePackages.npm
              nodePackages.typescript
              nodePackages.node-gyp
              python3
              gnumake
              gcc
              postgresql_16
              redis
              docker-compose
              
              # Nix development tools
              nixd
              alejandra
              statix
              deadnix
              nix-prefetch-git
              nix-prefetch-github
            ];
            
            shellHook = ''
              echo "Infisical development environment"
              echo "Run 'nix build' to build the backend package"
              echo "Run 'nix build .#frontend' to build the frontend package"
              echo "Run 'nix run .#checks.x86_64-linux.infisical-vm-test' to run VM tests"
            '';
          };
        });
      
      formatter = forAllSystems (system:
        treefmt-nix.lib.mkWrapper nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs = {
            alejandra.enable = true;
            prettier.enable = true;
          };
        });
    };
}