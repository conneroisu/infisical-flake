#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Infisical Flake Hash Updater${NC}"
echo "================================"

# Get the version from the flake or use provided argument
VERSION="${1:-0.97.4}"
echo -e "${YELLOW}Using Infisical version: ${VERSION}${NC}"

# Function to get source hash
get_source_hash() {
    echo -e "\n${YELLOW}Fetching source hash...${NC}"
    local hash=$(nix-prefetch-github Infisical infisical --rev "infisical-core/v${VERSION}" 2>/dev/null | jq -r .hash)
    if [ -z "$hash" ]; then
        echo -e "${RED}Failed to fetch source hash${NC}"
        exit 1
    fi
    echo -e "${GREEN}Source hash: ${hash}${NC}"
    echo "$hash"
}

# Function to get npm deps hash for a package
get_npm_deps_hash() {
    local package=$1
    echo -e "\n${YELLOW}Calculating npm deps hash for ${package}...${NC}"
    
    # Create temporary directory
    local tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT
    
    # Clone the repository
    echo "Cloning repository..."
    git clone --depth 1 --branch "infisical-core/v${VERSION}" \
        https://github.com/Infisical/infisical.git "$tmpdir/infisical" 2>/dev/null
    
    # Install dependencies and calculate hash
    cd "$tmpdir/infisical/${package}"
    echo "Installing npm dependencies..."
    npm ci --ignore-scripts 2>/dev/null
    
    # Calculate the hash
    local hash=$(nix hash path node_modules)
    echo -e "${GREEN}${package} npm deps hash: ${hash}${NC}"
    echo "$hash"
}

# Main execution
echo -e "\n${YELLOW}Step 1: Getting source repository hash${NC}"
SOURCE_HASH=$(get_source_hash)

echo -e "\n${YELLOW}Step 2: Getting backend npm dependencies hash${NC}"
echo "This may take a few minutes..."
BACKEND_NPM_HASH=$(get_npm_deps_hash "backend")

echo -e "\n${YELLOW}Step 3: Getting frontend npm dependencies hash${NC}"
echo "This may take a few minutes..."
FRONTEND_NPM_HASH=$(get_npm_deps_hash "frontend")

# Update the files
echo -e "\n${YELLOW}Step 4: Updating package files...${NC}"

# Update backend.nix
sed -i "s|hash = \"sha256-.*\"; # Use update-hashes.sh|hash = \"${SOURCE_HASH}\"; # Use update-hashes.sh|g" packages/backend.nix
sed -i "s|npmDepsHash = \"sha256-.*\"; # Use update-hashes.sh|npmDepsHash = \"${BACKEND_NPM_HASH}\"; # Use update-hashes.sh|g" packages/backend.nix

# Update frontend.nix
sed -i "s|hash = \"sha256-.*\"; # Use update-hashes.sh|hash = \"${SOURCE_HASH}\"; # Use update-hashes.sh|g" packages/frontend.nix
sed -i "s|npmDepsHash = \"sha256-.*\"; # Use update-hashes.sh|npmDepsHash = \"${FRONTEND_NPM_HASH}\"; # Use update-hashes.sh|g" packages/frontend.nix

echo -e "\n${GREEN}✅ Successfully updated all hashes!${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "  Version: ${VERSION}"
echo "  Source hash: ${SOURCE_HASH}"
echo "  Backend npm hash: ${BACKEND_NPM_HASH}"
echo "  Frontend npm hash: ${FRONTEND_NPM_HASH}"

echo -e "\n${GREEN}You can now build the packages:${NC}"
echo "  nix build .#backend"
echo "  nix build .#frontend"
echo "  nix build .#checks.x86_64-linux.infisical-vm-test"