{ lib
, stdenv
, fetchFromGitHub
, buildNpmPackage
, nodejs_20
, python3
, makeWrapper
, unixODBC
, freetds
, pkg-config
, knex-cli
, version ? "0.97.4"
}:

let
  nodejs = nodejs_20;
in buildNpmPackage rec {
  pname = "infisical-backend";
  inherit version;

  src = fetchFromGitHub {
    owner = "Infisical";
    repo = "infisical";
    rev = "infisical-core/v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Use update-hashes.sh to get correct hash
  };

  sourceRoot = "${src.name}/backend";
  
  # This hash needs to be updated when dependencies change
  # Run: nix-prefetch-git https://github.com/Infisical/infisical --rev infisical-core/v0.97.4 
  # Then run: nix hash path ./backend/node_modules after npm install
  npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Use update-hashes.sh to get correct hash

  nativeBuildInputs = [
    python3
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    unixODBC
    freetds
  ];

  # Configure npm build
  npmBuildScript = "build";
  
  # Set required environment variables for build
  preBuild = ''
    # Setup ODBC for TDS driver support
    export ODBCINI=$TMPDIR/odbc.ini
    export ODBCSYSINI=$TMPDIR
    
    cat > $TMPDIR/odbcinst.ini <<EOF
    [FreeTDS]
    Description = FreeTDS Driver
    Driver = ${freetds}/lib/libtdsodbc.so
    Setup = ${freetds}/lib/libtdsodbc.so
    FileUsage = 1
    EOF
  '';

  postInstall = ''
    # Create wrapper for the main application
    makeWrapper ${nodejs}/bin/node $out/bin/infisical-backend \
      --add-flags "$out/lib/node_modules/backend/dist/main.mjs" \
      --set NODE_ENV production \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}" \
      --set ODBCSYSINI ${placeholder "out"}/etc
    
    # Create migration wrapper
    makeWrapper ${nodejs}/bin/node $out/bin/infisical-migrate \
      --add-flags "-e" \
      --add-flags "\"require('child_process').execSync('cd $out/lib/node_modules/backend && npx knex migrate:latest --knexfile ./dist/db/knexfile.mjs', {stdio: 'inherit'})\"" \
      --set NODE_ENV production \
      --prefix PATH : "${lib.makeBinPath [ nodejs ]}" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath buildInputs}"
    
    # Copy ODBC configuration
    mkdir -p $out/etc
    cp $TMPDIR/odbcinst.ini $out/etc/
    
    # Create healthcheck script
    cat > $out/bin/infisical-healthcheck <<EOF
    #!${stdenv.shell}
    curl -f http://localhost:\''${PORT:-8080}/api/status || exit 1
    EOF
    chmod +x $out/bin/infisical-healthcheck
  '';

  meta = with lib; {
    description = "Infisical backend - Open-source secret management platform";
    homepage = "https://infisical.com";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.linux;
    mainProgram = "infisical-backend";
  };
}