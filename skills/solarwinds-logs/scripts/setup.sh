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

DOTNET_TOOLS_HELPER="$SKILL_DIR/scripts/lib/dotnet-tools.sh"
if [[ ! -f "$DOTNET_TOOLS_HELPER" ]]; then
    err "dotnet tools helper not found: $DOTNET_TOOLS_HELPER"
    exit 2
fi

# shellcheck source=lib/dotnet-tools.sh
source "$DOTNET_TOOLS_HELPER"

install_tool() {
    install_dotnet_tool "$PACKAGE_ID" "$VERSION" "$TOOLS_DIR" "$COMMAND"
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
ensure_dotnet_runtime
ensure_dotnet_tools_env
install_tool
check_env
