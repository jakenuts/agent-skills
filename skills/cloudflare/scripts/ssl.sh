#!/bin/bash
#
# Cloudflare SSL/TLS Management
# Created by After Dark Systems, LLC
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# Get SSL mode
get_mode() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings/ssl")

    if check_response "$response"; then
        local mode
        mode=$(echo "$response" | jq -r '.result.value')
        echo "SSL Mode: $mode"

        case "$mode" in
            off)
                echo "  No encryption (not recommended)"
                ;;
            flexible)
                echo "  Encrypts between visitor and Cloudflare only"
                ;;
            full)
                echo "  End-to-end encryption (origin can have self-signed cert)"
                ;;
            strict)
                echo "  End-to-end encryption (origin must have valid CA cert)"
                ;;
        esac
    else
        return 1
    fi
}

# Set SSL mode
set_mode() {
    local zone_id="$1"
    local mode="$2"

    if [[ -z "$zone_id" || -z "$mode" ]]; then
        echo -e "${RED}Error: Zone ID and mode required${NC}" >&2
        echo "Modes: off, flexible, full, strict"
        return 2
    fi

    echo -e "${BLUE}Setting SSL mode to: $mode${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/ssl" "{\"value\":\"$mode\"}")

    if check_response "$response"; then
        echo -e "${GREEN}SSL mode updated!${NC}"
    else
        return 1
    fi
}

# Get minimum TLS version
get_min_tls() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings/min_tls_version")

    if check_response "$response"; then
        echo "Minimum TLS Version: $(echo "$response" | jq -r '.result.value')"
    else
        return 1
    fi
}

# Set minimum TLS version
set_min_tls() {
    local zone_id="$1"
    local version="$2"

    if [[ -z "$zone_id" || -z "$version" ]]; then
        echo -e "${RED}Error: Zone ID and version required${NC}" >&2
        echo "Versions: 1.0, 1.1, 1.2, 1.3"
        return 2
    fi

    echo -e "${BLUE}Setting minimum TLS version to: $version${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/min_tls_version" "{\"value\":\"$version\"}")

    if check_response "$response"; then
        echo -e "${GREEN}Minimum TLS version updated!${NC}"
    else
        return 1
    fi
}

# Get TLS 1.3 setting
get_tls13() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings/tls_1_3")

    if check_response "$response"; then
        echo "TLS 1.3: $(echo "$response" | jq -r '.result.value')"
    else
        return 1
    fi
}

# Set TLS 1.3
set_tls13() {
    local zone_id="$1"
    local state="$2"

    if [[ -z "$zone_id" || -z "$state" ]]; then
        echo -e "${RED}Error: Zone ID and state required${NC}" >&2
        echo "States: on, off, zrt (0-RTT)"
        return 2
    fi

    echo -e "${BLUE}Setting TLS 1.3 to: $state${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/tls_1_3" "{\"value\":\"$state\"}")

    if check_response "$response"; then
        echo -e "${GREEN}TLS 1.3 setting updated!${NC}"
    else
        return 1
    fi
}

# Get Always Use HTTPS setting
get_always_https() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings/always_use_https")

    if check_response "$response"; then
        echo "Always Use HTTPS: $(echo "$response" | jq -r '.result.value')"
    else
        return 1
    fi
}

# Set Always Use HTTPS
set_always_https() {
    local zone_id="$1"
    local state="$2"

    if [[ -z "$zone_id" || -z "$state" ]]; then
        echo -e "${RED}Error: Zone ID and state (on/off) required${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}Setting Always Use HTTPS to: $state${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/always_use_https" "{\"value\":\"$state\"}")

    if check_response "$response"; then
        echo -e "${GREEN}Always Use HTTPS updated!${NC}"
    else
        return 1
    fi
}

# Get certificate packs
get_certs() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/ssl/certificate_packs")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "[\(.id)] \(.type) - \(.status) | Hosts: \(.hosts | join(", ")) | Expires: \(.validity_days // "N/A") days"
        '
    else
        return 1
    fi
}

# Get SSL verification status
get_verification() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/ssl/verification")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Get HSTS settings
get_hsts() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings/security_header")

    if check_response "$response"; then
        echo "$response" | jq '.result.value.strict_transport_security'
    else
        return 1
    fi
}

# Enable HSTS
enable_hsts() {
    local zone_id="$1"
    local max_age="${2:-31536000}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local data="{\"value\":{\"strict_transport_security\":{\"enabled\":true,\"max_age\":$max_age,\"include_subdomains\":true,\"preload\":false,\"nosniff\":true}}}"

    echo -e "${BLUE}Enabling HSTS with max-age: $max_age${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/security_header" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}HSTS enabled!${NC}"
    else
        return 1
    fi
}

# Get all SSL settings
get_all() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}SSL/TLS Settings:${NC}"
    echo "================"
    get_mode "$zone_id"
    echo ""
    get_min_tls "$zone_id"
    get_tls13 "$zone_id"
    get_always_https "$zone_id"
    echo ""
    echo -e "${BLUE}Certificate Packs:${NC}"
    get_certs "$zone_id"
}

usage() {
    cat << EOF
Cloudflare SSL/TLS Management
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> <zone_id> [options]

Commands:
    get-mode <zone_id>                  Get SSL mode
    set-mode <zone_id> <mode>           Set SSL mode
    get-min-tls <zone_id>               Get minimum TLS version
    set-min-tls <zone_id> <version>     Set minimum TLS version
    get-tls13 <zone_id>                 Get TLS 1.3 setting
    set-tls13 <zone_id> <state>         Set TLS 1.3 (on/off/zrt)
    get-always-https <zone_id>          Get Always Use HTTPS
    set-always-https <zone_id> <state>  Set Always Use HTTPS
    get-certs <zone_id>                 List certificate packs
    get-verification <zone_id>          Get SSL verification status
    get-hsts <zone_id>                  Get HSTS settings
    enable-hsts <zone_id> [max_age]     Enable HSTS
    get-all <zone_id>                   Show all SSL settings

SSL Modes:
    off        No encryption
    flexible   Flexible (origin not encrypted)
    full       Full (allows self-signed origin certs)
    strict     Full (strict) - requires valid CA cert

TLS Versions:
    1.0, 1.1, 1.2, 1.3

Examples:
    $(basename "$0") set-mode abc123 strict
    $(basename "$0") set-min-tls abc123 1.2
    $(basename "$0") set-always-https abc123 on
    $(basename "$0") enable-hsts abc123 31536000
    $(basename "$0") get-all abc123

EOF
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        get-mode)
            get_mode "$@"
            ;;
        set-mode)
            set_mode "$@"
            ;;
        get-min-tls)
            get_min_tls "$@"
            ;;
        set-min-tls)
            set_min_tls "$@"
            ;;
        get-tls13)
            get_tls13 "$@"
            ;;
        set-tls13)
            set_tls13 "$@"
            ;;
        get-always-https)
            get_always_https "$@"
            ;;
        set-always-https)
            set_always_https "$@"
            ;;
        get-certs)
            get_certs "$@"
            ;;
        get-verification)
            get_verification "$@"
            ;;
        get-hsts)
            get_hsts "$@"
            ;;
        enable-hsts)
            enable_hsts "$@"
            ;;
        get-all)
            get_all "$@"
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
