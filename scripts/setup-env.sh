#!/bin/bash
#
# Environment variable setup helpers for Agent Skills toolkit
#
# Provides reusable functions for checking and configuring required
# environment variables for various tools.
#
# Usage:
#   source scripts/setup-env.sh
#   check_env_var "SOLARWINDS_API_TOKEN" || prompt_env_var "SOLARWINDS_API_TOKEN" "SolarWinds API token"
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

# Check if an environment variable is set and non-empty
# Args: $1 = variable name
# Returns: 0 if set and non-empty, 1 otherwise
check_env_var() {
    local VAR_NAME="$1"
    local VAR_VALUE="${!VAR_NAME}"

    if [[ -n "$VAR_VALUE" ]]; then
        ok "$VAR_NAME is set"
        return 0
    else
        return 1
    fi
}

# Display environment variable setup guide
# Args: $1 = variable name, $2 = description
show_env_var_guide() {
    local VAR_NAME="$1"
    local DESCRIPTION="${2:-environment variable}"

    echo ""
    echo -e "${YELLOW}⚠️  $VAR_NAME Not Set${NC}"
    echo ""
    echo "This tool requires the $DESCRIPTION to be configured."
    echo ""
    echo -e "${CYAN}Setup Options:${NC}"
    echo ""
    echo "1. Set for current session:"
    echo "   export $VAR_NAME=\"your-value-here\""
    echo ""
    echo "2. Set permanently (bash):"
    echo "   echo 'export $VAR_NAME=\"your-value-here\"' >> ~/.bashrc"
    echo "   source ~/.bashrc"
    echo ""
    echo "3. Set permanently (zsh):"
    echo "   echo 'export $VAR_NAME=\"your-value-here\"' >> ~/.zshrc"
    echo "   source ~/.zshrc"
    echo ""
}

# Interactive prompt for environment variable setup
# Args: $1 = variable name, $2 = description, $3 = is_secret (true/false)
prompt_env_var() {
    local VAR_NAME="$1"
    local DESCRIPTION="${2:-environment variable}"
    local IS_SECRET="${3:-true}"

    echo ""
    echo -e "${YELLOW}⚠️  $VAR_NAME Not Set${NC}"
    echo ""
    echo "This tool requires the $DESCRIPTION."
    echo ""
    read -p "Would you like to set it now? (y/N): " response
    echo ""

    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        show_env_var_guide "$VAR_NAME" "$DESCRIPTION"
        return 1
    fi

    local value
    if [[ "$IS_SECRET" == "true" ]]; then
        read -sp "Enter your $DESCRIPTION: " value
        echo ""
    else
        read -p "Enter your $DESCRIPTION: " value
    fi

    if [[ -z "$value" ]]; then
        err "No value provided"
        return 1
    fi

    # Set for current session
    export "$VAR_NAME=$value"
    ok "$VAR_NAME set for current session"

    # Offer to make permanent
    echo ""
    read -p "Make permanent in shell configuration? (y/N): " permanent
    if [[ "$permanent" =~ ^[Yy]$ ]]; then
        # Detect shell
        local SHELL_RC=""
        if [[ -n "$BASH_VERSION" ]]; then
            SHELL_RC="$HOME/.bashrc"
        elif [[ -n "$ZSH_VERSION" ]]; then
            SHELL_RC="$HOME/.zshrc"
        else
            # Try to detect from SHELL variable
            if [[ "$SHELL" == *"zsh"* ]]; then
                SHELL_RC="$HOME/.zshrc"
            else
                SHELL_RC="$HOME/.bashrc"
            fi
        fi

        echo "export $VAR_NAME=\"$value\"" >> "$SHELL_RC"
        ok "Added to $SHELL_RC"
        info "Restart your terminal or run: source $SHELL_RC"
    fi

    return 0
}

# Check multiple environment variables
# Args: space-separated list of variable names
# Returns: 0 if all are set, 1 if any are missing
check_env_vars() {
    local ALL_SET=true

    for VAR_NAME in "$@"; do
        if ! check_env_var "$VAR_NAME"; then
            warn "$VAR_NAME is not set"
            ALL_SET=false
        fi
    done

    if [[ "$ALL_SET" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# SolarWinds-specific setup helper
setup_solarwinds_env() {
    if check_env_var "SOLARWINDS_API_TOKEN"; then
        return 0
    fi

    echo ""
    echo -e "${CYAN}SolarWinds API Token Required${NC}"
    echo ""
    echo "The SolarWinds log search tool requires an API token for authentication."
    echo ""
    echo "To obtain a token:"
    echo "  1. Log in to SolarWinds Observability"
    echo "  2. Navigate to Settings → API Tokens"
    echo "  3. Create a new token with 'Logs Read' permission"
    echo ""

    prompt_env_var "SOLARWINDS_API_TOKEN" "SolarWinds API token" "true"
}

# Export functions for use by other scripts
export -f check_env_var
export -f show_env_var_guide
export -f prompt_env_var
export -f check_env_vars
export -f setup_solarwinds_env
