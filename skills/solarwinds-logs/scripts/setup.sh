#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$SKILL_DIR/tools"
PACKAGE_ID="DealerVision.SolarWindsLogSearch"
VERSION="2.4.0"
COMMAND="logs"
DOTNET_CHANNEL="10.0"

step() { echo ""; echo ">> $1"; }
ok() { echo "   OK: $1"; }
warn() { echo "   WARN: $1"; }
err() { echo "   ERROR: $1" >&2; }

SHARED_DOTNET_ENV="$SKILL_DIR/../_shared/scripts/dotnet-env.sh"
if [[ ! -f "$SHARED_DOTNET_ENV" ]]; then
    err "Shared dotnet helper not found: $SHARED_DOTNET_ENV"
    exit 2
fi

# shellcheck source=../../_shared/scripts/dotnet-env.sh
source "$SHARED_DOTNET_ENV"
dotnet_env

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
