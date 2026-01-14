#!/bin/bash
#
# Cloudflare Zone Management
# Created by After Dark Systems, LLC
#
# Manage Cloudflare zones (domains)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# List all zones
list_zones() {
    local page="${1:-1}"
    local per_page="${2:-50}"
    local name_filter="${3:-}"

    local endpoint="/zones?page=$page&per_page=$per_page"

    if [[ -n "$name_filter" ]]; then
        endpoint="${endpoint}&name=$name_filter"
    fi

    local response
    response=$(cf_request "GET" "$endpoint")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "[\(.id)] \(.name) - Status: \(.status) | Plan: \(.plan.name) | NS: \(.name_servers | join(", "))"
        '

        # Show pagination info
        local total_pages total_count
        total_pages=$(echo "$response" | jq -r '.result_info.total_pages')
        total_count=$(echo "$response" | jq -r '.result_info.total_count')
        echo ""
        echo -e "${BLUE}Page $page of $total_pages (Total zones: $total_count)${NC}"
    else
        return 1
    fi
}

# List zones as JSON
list_zones_json() {
    local page="${1:-1}"
    local per_page="${2:-50}"

    local response
    response=$(cf_request "GET" "/zones?page=$page&per_page=$per_page")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Get zone details
get_zone() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Get zone by name
get_zone_by_name() {
    local domain="$1"
    local id_only="${2:-false}"

    if [[ -z "$domain" ]]; then
        echo -e "${RED}Error: Domain name required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones?name=$domain")

    if check_response "$response"; then
        local count
        count=$(echo "$response" | jq -r '.result_info.count')

        if [[ "$count" -eq 0 ]]; then
            echo -e "${YELLOW}Zone not found: $domain${NC}" >&2
            return 4
        fi

        if [[ "$id_only" == "true" || "$id_only" == "--id-only" ]]; then
            echo "$response" | jq -r '.result[0].id'
        else
            echo "$response" | jq '.result[0]'
        fi
    else
        return 1
    fi
}

# Create a new zone
create_zone() {
    local domain="$1"
    local account_id="$2"
    local type="${3:-full}"
    local jump_start="${4:-true}"

    if [[ -z "$domain" ]]; then
        echo -e "${RED}Error: Domain name required${NC}" >&2
        return 2
    fi

    local data
    if [[ -n "$account_id" ]]; then
        data=$(jq -n \
            --arg name "$domain" \
            --arg account_id "$account_id" \
            --arg type "$type" \
            --argjson jump_start "$jump_start" \
            '{name: $name, account: {id: $account_id}, type: $type, jump_start: $jump_start}')
    else
        # Get first account
        local accounts_response
        accounts_response=$(cf_request "GET" "/accounts")
        account_id=$(echo "$accounts_response" | jq -r '.result[0].id')

        data=$(jq -n \
            --arg name "$domain" \
            --arg account_id "$account_id" \
            --arg type "$type" \
            --argjson jump_start "$jump_start" \
            '{name: $name, account: {id: $account_id}, type: $type, jump_start: $jump_start}')
    fi

    echo -e "${BLUE}Creating zone: $domain${NC}"
    local response
    response=$(cf_request "POST" "/zones" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}Zone created successfully!${NC}"
        echo ""
        echo "Zone ID: $(echo "$response" | jq -r '.result.id')"
        echo "Status: $(echo "$response" | jq -r '.result.status')"
        echo ""
        echo -e "${YELLOW}Update your domain's nameservers to:${NC}"
        echo "$response" | jq -r '.result.name_servers[]'
    else
        return 1
    fi
}

# Delete a zone
delete_zone() {
    local zone_id="$1"
    local confirm="${2:-}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        echo -e "${YELLOW}Warning: This will permanently delete the zone!${NC}"
        echo "To confirm, run: $(basename "$0") delete $zone_id --confirm"
        return 0
    fi

    echo -e "${BLUE}Deleting zone: $zone_id${NC}"
    local response
    response=$(cf_request "DELETE" "/zones/$zone_id")

    if check_response "$response"; then
        echo -e "${GREEN}Zone deleted successfully!${NC}"
    else
        return 1
    fi
}

# Trigger zone activation check
activation_check() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}Triggering activation check for zone: $zone_id${NC}"
    local response
    response=$(cf_request "PUT" "/zones/$zone_id/activation_check")

    if check_response "$response"; then
        echo -e "${GREEN}Activation check triggered!${NC}"
        print_result "$response"
    else
        return 1
    fi
}

# Get zone ID helper (for other scripts)
get_zone_id() {
    local identifier="$1"

    # Check if it looks like a zone ID (32 hex chars)
    if [[ "$identifier" =~ ^[a-f0-9]{32}$ ]]; then
        echo "$identifier"
    else
        # Assume it's a domain name
        get_zone_by_name "$identifier" --id-only
    fi
}

# Usage information
usage() {
    cat << EOF
Cloudflare Zone Management
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> [options]

Commands:
    list [page] [per_page]              List all zones
    list-json [page] [per_page]         List zones as JSON
    get <zone_id>                       Get zone details by ID
    get-by-name <domain> [--id-only]    Get zone by domain name
    create <domain> [account_id]        Create a new zone
    delete <zone_id> [--confirm]        Delete a zone
    activation-check <zone_id>          Trigger activation check
    get-id <domain_or_id>               Get zone ID (resolves domain to ID)

Examples:
    $(basename "$0") list
    $(basename "$0") get abc123def456
    $(basename "$0") get-by-name example.com
    $(basename "$0") get-by-name example.com --id-only
    $(basename "$0") create example.com
    $(basename "$0") delete abc123def456 --confirm

EOF
}

# Main
main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        list)
            list_zones "$@"
            ;;
        list-json)
            list_zones_json "$@"
            ;;
        get)
            get_zone "$@"
            ;;
        get-by-name)
            get_zone_by_name "$@"
            ;;
        create)
            create_zone "$@"
            ;;
        delete)
            delete_zone "$@"
            ;;
        activation-check)
            activation_check "$@"
            ;;
        get-id)
            get_zone_id "$@"
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
