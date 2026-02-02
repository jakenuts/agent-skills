#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$SKILL_DIR/tools"
PACKAGE_ID="DealerVision.SolarWindsLogSearch"
VERSION="2.4.0"
COMMAND="logs"
DOTNET_CHANNEL="10.0"
DOTNET_INSTALL_DIR="$HOME/.dotnet"

export DOTNET_ROOT="$DOTNET_INSTALL_DIR"
export DOTNET_ROOT_X64="$DOTNET_INSTALL_DIR"
export PATH="$DOTNET_INSTALL_DIR:$DOTNET_INSTALL_DIR/tools:$PATH"

step() { echo ""; echo ">> $1"; }
ok() { echo "   OK: $1"; }
warn() { echo "   WARN: $1"; }
err() { echo "   ERROR: $1" >&2; }

ensure_dotnet() {
    if command -v dotnet >/dev/null 2>&1; then
        local version
        version="$(dotnet --version 2>/dev/null || echo "0.0.0")"
        local major="${version%%.*}"
        if [[ "$major" -ge 10 ]]; then
            ok ".NET SDK $version detected"
            return 0
        fi
        warn ".NET SDK $version found, but 10.0+ is required"
    else
        warn ".NET SDK not found"
    fi

    step "Installing .NET SDK $DOTNET_CHANNEL"

    if ! command -v curl >/dev/null 2>&1; then
        err "curl is required to install .NET. Install curl and rerun this script."
        exit 2
    fi

    local installer
    installer="$(mktemp)"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$installer"
    bash "$installer" --channel "$DOTNET_CHANNEL" --install-dir "$DOTNET_INSTALL_DIR"
    rm -f "$installer"

    ok ".NET SDK installed to $DOTNET_INSTALL_DIR"
    warn "Add $DOTNET_INSTALL_DIR and $DOTNET_INSTALL_DIR/tools to your PATH for future shells"
}

install_tool() {
    if [[ ! -d "$TOOLS_DIR" ]]; then
        err "Tool package directory not found: $TOOLS_DIR"
        exit 2
    fi

    if dotnet tool list --global 2>/dev/null | grep -qi "$PACKAGE_ID"; then
        ok "Tool already installed: $PACKAGE_ID"
        return 0
    fi

    step "Installing $PACKAGE_ID v$VERSION"
    dotnet tool install --global "$PACKAGE_ID" --version "$VERSION" --add-source "$TOOLS_DIR"

    if command -v "$COMMAND" >/dev/null 2>&1; then
        ok "Tool installed: $COMMAND"
    else
        warn "Tool installed but '$COMMAND' is not on PATH. Restart your shell and try again."
    fi
}

check_env() {
    if [[ -z "${SOLARWINDS_API_TOKEN:-}" ]]; then
        warn "SOLARWINDS_API_TOKEN is not set"
        echo "Set it with: export SOLARWINDS_API_TOKEN=\"your-token-here\""
    else
        ok "SOLARWINDS_API_TOKEN is set"
    fi
}

step "SolarWinds Logs Setup"
ensure_dotnet
install_tool
check_env
