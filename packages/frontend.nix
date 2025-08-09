{ lib
, stdenv
, fetchFromGitHub
, buildNpmPackage
, nodejs_20
, version ? "0.97.4"
}:

let
  nodejs = nodejs_20;
in buildNpmPackage rec {
  pname = "infisical-frontend";
  inherit version;

  src = fetchFromGitHub {
    owner = "Infisical";
    repo = "infisical";
    rev = "infisical-core/v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Use update-hashes.sh to get correct hash
  };

  sourceRoot = "${src.name}/frontend";
  
  # This hash needs to be updated when dependencies change
  npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Use update-hashes.sh to get correct hash

  npmBuildScript = "build";
  
  # Next.js specific build configuration
  preBuild = ''
    # Set Next.js build mode
    export NEXT_TELEMETRY_DISABLED=1
    export NODE_ENV=production
  '';

  installPhase = ''
    runHook preInstall
    
    # Create output directories
    mkdir -p $out/share/infisical-frontend
    
    # Copy built Next.js application
    cp -r .next $out/share/infisical-frontend/
    cp -r public $out/share/infisical-frontend/
    cp package*.json $out/share/infisical-frontend/
    
    # Copy node_modules for runtime dependencies
    cp -r node_modules $out/share/infisical-frontend/
    
    # Create a start script
    cat > $out/bin/infisical-frontend <<EOF
    #!${stdenv.shell}
    cd $out/share/infisical-frontend
    exec ${nodejs}/bin/node .next/standalone/server.js
    EOF
    chmod +x $out/bin/infisical-frontend
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "Infisical frontend - Web interface for secret management";
    homepage = "https://infisical.com";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.linux;
    mainProgram = "infisical-frontend";
  };
}