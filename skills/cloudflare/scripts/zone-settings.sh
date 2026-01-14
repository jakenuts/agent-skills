#!/bin/bash
#
# Cloudflare Zone Settings Management
# Created by After Dark Systems, LLC
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# List all settings
list_settings() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "\(.id): \(.value)"
        '
    else
        return 1
    fi
}

# Get specific setting
get_setting() {
    local zone_id="$1"
    local setting="$2"

    if [[ -z "$zone_id" || -z "$setting" ]]; then
        echo -e "${RED}Error: Zone ID and setting name required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings/$setting")

    if check_response "$response"; then
        echo "$setting: $(echo "$response" | jq -r '.result.value')"
    else
        return 1
    fi
}

# Set a setting
set_setting() {
    local zone_id="$1"
    local setting="$2"
    local value="$3"

    if [[ -z "$zone_id" || -z "$setting" || -z "$value" ]]; then
        echo -e "${RED}Error: Zone ID, setting, and value required${NC}" >&2
        return 2
    fi

    local data
    # Check if value is a JSON object or simple value
    if [[ "$value" == "{"* ]]; then
        data="{\"value\":$value}"
    elif [[ "$value" == "true" || "$value" == "false" ]]; then
        data="{\"value\":$value}"
    elif [[ "$value" =~ ^[0-9]+$ ]]; then
        data="{\"value\":$value}"
    else
        data="{\"value\":\"$value\"}"
    fi

    echo -e "${BLUE}Setting $setting to: $value${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/$setting" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}Setting updated!${NC}"
    else
        return 1
    fi
}

# Set security level
set_security_level() {
    local zone_id="$1"
    local level="$2"

    if [[ -z "$zone_id" || -z "$level" ]]; then
        echo -e "${RED}Error: Zone ID and level required${NC}" >&2
        echo "Levels: off, essentially_off, low, medium, high, under_attack"
        return 2
    fi

    set_setting "$zone_id" "security_level" "$level"
}

# Enable Under Attack Mode
under_attack_mode() {
    local zone_id="$1"
    local state="${2:-on}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    if [[ "$state" == "on" ]]; then
        echo -e "${YELLOW}Enabling Under Attack Mode!${NC}"
        set_setting "$zone_id" "security_level" "under_attack"
    else
        echo -e "${BLUE}Disabling Under Attack Mode (setting to high)${NC}"
        set_setting "$zone_id" "security_level" "high"
    fi
}

# Toggle minification
set_minify() {
    local zone_id="$1"
    local css="${2:-on}"
    local html="${3:-on}"
    local js="${4:-on}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local value="{\"css\":\"$css\",\"html\":\"$html\",\"js\":\"$js\"}"
    set_setting "$zone_id" "minify" "$value"
}

# Enable/disable features
toggle_feature() {
    local zone_id="$1"
    local feature="$2"
    local state="$3"

    if [[ -z "$zone_id" || -z "$feature" || -z "$state" ]]; then
        echo -e "${RED}Error: Zone ID, feature, and state (on/off) required${NC}" >&2
        return 2
    fi

    set_setting "$zone_id" "$feature" "$state"
}

# Get important settings summary
get_summary() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}Zone Settings Summary${NC}"
    echo "====================="
    echo ""

    local settings=("ssl" "security_level" "always_use_https" "min_tls_version" "browser_cache_ttl" "development_mode" "rocket_loader" "email_obfuscation" "hotlink_protection" "ip_geolocation")

    for setting in "${settings[@]}"; do
        local response
        response=$(cf_request "GET" "/zones/$zone_id/settings/$setting" 2>/dev/null)
        if check_response "$response" 2>/dev/null; then
            echo "$setting: $(echo "$response" | jq -r '.result.value')"
        fi
    done
}

usage() {
    cat << EOF
Cloudflare Zone Settings
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> <zone_id> [options]

Commands:
    list <zone_id>                          List all settings
    get <zone_id> <setting>                 Get specific setting
    set <zone_id> <setting> <value>         Set a setting
    summary <zone_id>                       Show important settings

    security-level <zone_id> <level>        Set security level
    under-attack <zone_id> [on|off]         Toggle Under Attack Mode
    minify <zone_id> [css] [html] [js]      Set minification (on/off each)
    toggle <zone_id> <feature> <on|off>     Toggle a feature

Security Levels:
    off, essentially_off, low, medium, high, under_attack

Common Settings:
    always_use_https      on/off
    automatic_https_rewrites  on/off
    browser_cache_ttl     0-31536000 (seconds)
    browser_check         on/off
    cache_level           bypass, basic, simplified, aggressive
    development_mode      on/off
    email_obfuscation     on/off
    hotlink_protection    on/off
    ip_geolocation        on/off
    opportunistic_encryption  on/off
    rocket_loader         on/off/manual
    websockets            on/off

Examples:
    $(basename "$0") summary abc123
    $(basename "$0") get abc123 ssl
    $(basename "$0") set abc123 always_use_https on
    $(basename "$0") security-level abc123 high
    $(basename "$0") under-attack abc123 on
    $(basename "$0") minify abc123 on on off

EOF
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        list)
            list_settings "$@"
            ;;
        get)
            get_setting "$@"
            ;;
        set)
            set_setting "$@"
            ;;
        summary)
            get_summary "$@"
            ;;
        security-level)
            set_security_level "$@"
            ;;
        under-attack)
            under_attack_mode "$@"
            ;;
        minify)
            set_minify "$@"
            ;;
        toggle)
            toggle_feature "$@"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            usage
            exit 2
            ;;
    esac
}

main "$@"
