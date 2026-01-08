#!/bin/bash
#
# Shared prerequisite installation for Agent Skills toolkit
#
# This script provides reusable functions for checking and installing
# prerequisites that may be shared across multiple tools.
#
# Usage:
#   source scripts/install-prerequisites.sh
#   check_dotnet_sdk || install_dotnet_sdk_guide
#

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# Helpers
ok() { echo -e "   ${GREEN}✓ $1${NC}"; }
warn() { echo -e "   ${YELLOW}⚠️  $1${NC}"; }
err() { echo -e "   ${RED}✗ $1${NC}"; }
info() { echo -e "   ${GRAY}$1${NC}"; }

# Check if .NET SDK is installed and meets minimum version
# Returns: 0 if installed and valid, 1 otherwise
check_dotnet_sdk() {
    local MIN_VERSION=${1:-10}

    if ! command -v dotnet &> /dev/null; then
        return 1
    fi

    local DOTNET_VERSION=$(dotnet --version 2>/dev/null || echo "0.0.0")
    local MAJOR_VERSION=$(echo "$DOTNET_VERSION" | cut -d. -f1)

    if [[ "$MAJOR_VERSION" -lt "$MIN_VERSION" ]]; then
        warn ".NET SDK $DOTNET_VERSION found, but version $MIN_VERSION.0+ required"
        return 1
    fi

    ok ".NET SDK $DOTNET_VERSION installed"
    return 0
}

# Display installation guide for .NET SDK
install_dotnet_sdk_guide() {
    local MIN_VERSION=${1:-10}

    echo ""
    echo -e "${YELLOW}⚠️  .NET SDK $MIN_VERSION.0+ Required${NC}"
    echo ""
    echo "This tool requires the .NET SDK to install and run."
    echo ""
    echo -e "${CYAN}Installation Options:${NC}"
    echo ""
    echo "1. Official installer (recommended):"
    echo "   https://dotnet.microsoft.com/download"
    echo ""
    echo "2. Quick install script (Linux/macOS):"
    echo "   wget https://dot.net/v1/dotnet-install.sh"
    echo "   chmod +x dotnet-install.sh"
    echo "   ./dotnet-install.sh --channel $MIN_VERSION.0"
    echo "   export PATH=\"\$HOME/.dotnet:\$PATH\""
    echo ""
    echo "3. Package manager:"
    echo "   # Ubuntu/Debian"
    echo "   sudo apt-get update"
    echo "   sudo apt-get install -y dotnet-sdk-$MIN_VERSION.0"
    echo ""
    echo "   # macOS"
    echo "   brew install dotnet@$MIN_VERSION"
    echo ""
    echo -e "${GRAY}Note: .NET $MIN_VERSION SDK can also build .NET 8/9 projects${NC}"
    echo ""
}

# Check if a .NET tool is installed globally
# Args: $1 = package ID
# Returns: 0 if installed, 1 otherwise
check_dotnet_tool() {
    local PACKAGE_ID="$1"

    if ! command -v dotnet &> /dev/null; then
        return 1
    fi

    if dotnet tool list --global 2>/dev/null | grep -qi "$PACKAGE_ID"; then
        local INSTALLED=$(dotnet tool list --global 2>/dev/null | grep -i "$PACKAGE_ID")
        ok "Tool already installed: $INSTALLED"
        return 0
    fi

    return 1
}

# Install a .NET tool from a local NuGet package
# Args: $1 = package ID, $2 = version, $3 = source path
install_dotnet_tool_local() {
    local PACKAGE_ID="$1"
    local VERSION="$2"
    local SOURCE_PATH="$3"

    info "Installing $PACKAGE_ID v$VERSION from $SOURCE_PATH..."

    if dotnet tool install --global "$PACKAGE_ID" --version "$VERSION" --add-source "$SOURCE_PATH" 2>&1; then
        ok "Installed: $PACKAGE_ID v$VERSION"
        return 0
    else
        err "Failed to install $PACKAGE_ID"
        return 1
    fi
}

# Uninstall a .NET tool
# Args: $1 = package ID
uninstall_dotnet_tool() {
    local PACKAGE_ID="$1"

    if check_dotnet_tool "$PACKAGE_ID"; then
        info "Uninstalling $PACKAGE_ID..."
        if dotnet tool uninstall --global "$PACKAGE_ID" 2>&1; then
            ok "Uninstalled: $PACKAGE_ID"
            return 0
        else
            err "Failed to uninstall $PACKAGE_ID"
            return 1
        fi
    else
        info "$PACKAGE_ID is not installed"
        return 0
    fi
}

# Export functions for use by other scripts
export -f check_dotnet_sdk
export -f install_dotnet_sdk_guide
export -f check_dotnet_tool
export -f install_dotnet_tool_local
export -f uninstall_dotnet_tool
