#!/bin/bash
#
# Cloudflare Workers Management
# Created by After Dark Systems, LLC
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# Get account ID
get_account_id() {
    local response
    response=$(cf_request "GET" "/accounts?per_page=1")

    if check_response "$response" 2>/dev/null; then
        echo "$response" | jq -r '.result[0].id'
    else
        echo ""
    fi
}

# List workers
list_workers() {
    local account_id="${1:-$(get_account_id)}"

    if [[ -z "$account_id" ]]; then
        echo -e "${RED}Error: Could not determine account ID${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/accounts/$account_id/workers/scripts")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "[\(.id)] \(.id) - Modified: \(.modified_on // "N/A")"
        '
        local count
        count=$(echo "$response" | jq -r '.result | length')
        echo ""
        echo -e "${BLUE}Found $count worker(s)${NC}"
    else
        return 1
    fi
}

# Get worker script
get_worker() {
    local script_name="$1"
    local account_id="${2:-$(get_account_id)}"

    if [[ -z "$script_name" ]]; then
        echo -e "${RED}Error: Script name required${NC}" >&2
        return 2
    fi

    if [[ -z "$account_id" ]]; then
        echo -e "${RED}Error: Could not determine account ID${NC}" >&2
        return 2
    fi

    load_credentials

    local url="https://api.cloudflare.com/client/v4/accounts/$account_id/workers/scripts/$script_name"

    if [[ -n "$CF_API_TOKEN" ]]; then
        curl -s "$url" -H "Authorization: Bearer $CF_API_TOKEN"
    else
        curl -s "$url" -H "X-Auth-Key: $CF_GLOBAL_KEY"
    fi
}

# Deploy worker
deploy_worker() {
    local script_name="$1"
    local script_file="$2"
    local account_id="${3:-$(get_account_id)}"

    if [[ -z "$script_name" || -z "$script_file" ]]; then
        echo -e "${RED}Error: Script name and file required${NC}" >&2
        return 2
    fi

    if [[ ! -f "$script_file" ]]; then
        echo -e "${RED}Error: File not found: $script_file${NC}" >&2
        return 2
    fi

    if [[ -z "$account_id" ]]; then
        echo -e "${RED}Error: Could not determine account ID${NC}" >&2
        return 2
    fi

    load_credentials

    echo -e "${BLUE}Deploying worker: $script_name${NC}"
    local url="https://api.cloudflare.com/client/v4/accounts/$account_id/workers/scripts/$script_name"

    local response
    if [[ -n "$CF_API_TOKEN" ]]; then
        response=$(curl -s -X PUT "$url" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/javascript" \
            --data-binary "@$script_file")
    else
        response=$(curl -s -X PUT "$url" \
            -H "X-Auth-Key: $CF_GLOBAL_KEY" \
            -H "Content-Type: application/javascript" \
            --data-binary "@$script_file")
    fi

    if check_response "$response"; then
        echo -e "${GREEN}Worker deployed successfully!${NC}"
        print_result "$response"
    else
        return 1
    fi
}

# Delete worker
delete_worker() {
    local script_name="$1"
    local confirm="${2:-}"
    local account_id="${3:-$(get_account_id)}"

    if [[ -z "$script_name" ]]; then
        echo -e "${RED}Error: Script name required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        echo -e "${YELLOW}Warning: This will delete the worker!${NC}"
        echo "To confirm: $(basename "$0") delete $script_name --confirm"
        return 0
    fi

    if [[ -z "$account_id" ]]; then
        echo -e "${RED}Error: Could not determine account ID${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "DELETE" "/accounts/$account_id/workers/scripts/$script_name")

    if check_response "$response"; then
        echo -e "${GREEN}Worker deleted!${NC}"
    else
        return 1
    fi
}

# List worker routes for a zone
list_routes() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/workers/routes")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "[\(.id)] \(.pattern) -> \(.script // "No worker")"
        '
    else
        return 1
    fi
}

# Create worker route
create_route() {
    local zone_id="$1"
    local pattern="$2"
    local script="${3:-}"

    if [[ -z "$zone_id" || -z "$pattern" ]]; then
        echo -e "${RED}Error: Zone ID and pattern required${NC}" >&2
        return 2
    fi

    local data
    if [[ -n "$script" ]]; then
        data=$(jq -n --arg pattern "$pattern" --arg script "$script" '{pattern: $pattern, script: $script}')
    else
        data=$(jq -n --arg pattern "$pattern" '{pattern: $pattern}')
    fi

    echo -e "${BLUE}Creating route: $pattern${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/workers/routes" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}Route created!${NC}"
        print_result "$response"
    else
        return 1
    fi
}

# Delete worker route
delete_route() {
    local zone_id="$1"
    local route_id="$2"
    local confirm="${3:-}"

    if [[ -z "$zone_id" || -z "$route_id" ]]; then
        echo -e "${RED}Error: Zone ID and Route ID required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        echo -e "${YELLOW}To confirm: $(basename "$0") delete-route $zone_id $route_id --confirm${NC}"
        return 0
    fi

    local response
    response=$(cf_request "DELETE" "/zones/$zone_id/workers/routes/$route_id")

    if check_response "$response"; then
        echo -e "${GREEN}Route deleted!${NC}"
    else
        return 1
    fi
}

# Get worker usage
get_usage() {
    local account_id="${1:-$(get_account_id)}"

    if [[ -z "$account_id" ]]; then
        echo -e "${RED}Error: Could not determine account ID${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/accounts/$account_id/workers/account-settings")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

usage() {
    cat << EOF
Cloudflare Workers Management
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> [options]

Commands:
    list [account_id]                       List all workers
    get <script_name> [account_id]          Get worker script
    deploy <script_name> <file> [acct_id]   Deploy worker
    delete <script_name> [--confirm]        Delete worker

    list-routes <zone_id>                   List worker routes
    create-route <zone_id> <pattern> [script]  Create route
    delete-route <zone_id> <route_id> [--confirm]  Delete route

    usage [account_id]                      Get workers usage/limits

Route Pattern Examples:
    example.com/*
    *.example.com/api/*
    example.com/admin*

Examples:
    $(basename "$0") list
    $(basename "$0") deploy my-worker ./worker.js
    $(basename "$0") list-routes abc123
    $(basename "$0") create-route abc123 "example.com/api/*" my-worker
    $(basename "$0") delete my-worker --confirm

EOF
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        list)
            list_workers "$@"
            ;;
        get)
            get_worker "$@"
            ;;
        deploy)
            deploy_worker "$@"
            ;;
        delete)
            delete_worker "$@"
            ;;
        list-routes)
            list_routes "$@"
            ;;
        create-route)
            create_route "$@"
            ;;
        delete-route)
            delete_route "$@"
            ;;
        usage)
            get_usage "$@"
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
