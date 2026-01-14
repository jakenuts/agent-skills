#!/bin/bash
#
# Cloudflare Page Rules Management
# Created by After Dark Systems, LLC
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# List page rules
list_rules() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/pagerules")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "[\(.id)] Priority: \(.priority) | Status: \(.status)",
            "  URL: \(.targets[0].constraint.value)",
            "  Actions: \(.actions | map("\(.id)=\(.value // "enabled")") | join(", "))",
            ""
        '
        local count
        count=$(echo "$response" | jq -r '.result | length')
        echo -e "${BLUE}Found $count page rule(s)${NC}"
    else
        return 1
    fi
}

# Get page rule
get_rule() {
    local zone_id="$1"
    local rule_id="$2"

    if [[ -z "$zone_id" || -z "$rule_id" ]]; then
        echo -e "${RED}Error: Zone ID and Rule ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/pagerules/$rule_id")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Create page rule
create_rule() {
    local zone_id="$1"
    shift || true

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local url="" actions="[]" priority="1" status="active"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --url)
                url="$2"
                shift 2
                ;;
            --actions)
                actions="$2"
                shift 2
                ;;
            --priority)
                priority="$2"
                shift 2
                ;;
            --status)
                status="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$url" ]]; then
        echo -e "${RED}Error: --url is required${NC}" >&2
        return 2
    fi

    local data
    data=$(jq -n \
        --arg url "$url" \
        --argjson actions "$actions" \
        --argjson priority "$priority" \
        --arg status "$status" \
        '{
            targets: [{target: "url", constraint: {operator: "matches", value: $url}}],
            actions: $actions,
            priority: $priority,
            status: $status
        }')

    echo -e "${BLUE}Creating page rule for: $url${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/pagerules" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}Page rule created!${NC}"
        print_result "$response"
    else
        return 1
    fi
}

# Delete page rule
delete_rule() {
    local zone_id="$1"
    local rule_id="$2"
    local confirm="${3:-}"

    if [[ -z "$zone_id" || -z "$rule_id" ]]; then
        echo -e "${RED}Error: Zone ID and Rule ID required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        echo -e "${YELLOW}Warning: This will delete the page rule!${NC}"
        get_rule "$zone_id" "$rule_id"
        echo ""
        echo "To confirm: $(basename "$0") delete $zone_id $rule_id --confirm"
        return 0
    fi

    local response
    response=$(cf_request "DELETE" "/zones/$zone_id/pagerules/$rule_id")

    if check_response "$response"; then
        echo -e "${GREEN}Page rule deleted!${NC}"
    else
        return 1
    fi
}

# Quick create: Cache Everything
cache_everything() {
    local zone_id="$1"
    local url="$2"
    local edge_ttl="${3:-86400}"

    if [[ -z "$zone_id" || -z "$url" ]]; then
        echo -e "${RED}Error: Zone ID and URL pattern required${NC}" >&2
        return 2
    fi

    local actions="[{\"id\":\"cache_level\",\"value\":\"cache_everything\"},{\"id\":\"edge_cache_ttl\",\"value\":$edge_ttl}]"
    create_rule "$zone_id" --url "$url" --actions "$actions"
}

# Quick create: Forwarding URL
forwarding_rule() {
    local zone_id="$1"
    local from_url="$2"
    local to_url="$3"
    local status_code="${4:-301}"

    if [[ -z "$zone_id" || -z "$from_url" || -z "$to_url" ]]; then
        echo -e "${RED}Error: Zone ID, from URL, and to URL required${NC}" >&2
        return 2
    fi

    local actions="[{\"id\":\"forwarding_url\",\"value\":{\"url\":\"$to_url\",\"status_code\":$status_code}}]"
    create_rule "$zone_id" --url "$from_url" --actions "$actions"
}

# Quick create: Always HTTPS
always_https() {
    local zone_id="$1"
    local url="${2:-*}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local actions='[{"id":"always_use_https"}]'
    create_rule "$zone_id" --url "$url" --actions "$actions"
}

# Quick create: Bypass cache
bypass_cache() {
    local zone_id="$1"
    local url="$2"

    if [[ -z "$zone_id" || -z "$url" ]]; then
        echo -e "${RED}Error: Zone ID and URL pattern required${NC}" >&2
        return 2
    fi

    local actions='[{"id":"cache_level","value":"bypass"}]'
    create_rule "$zone_id" --url "$url" --actions "$actions"
}

# Quick create: Disable security
disable_security() {
    local zone_id="$1"
    local url="$2"
    local confirm="${3:-}"

    if [[ -z "$zone_id" || -z "$url" ]]; then
        echo -e "${RED}Error: Zone ID and URL pattern required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        echo -e "${YELLOW}Warning: This disables security features for matching URLs!${NC}"
        echo "To confirm: $(basename "$0") disable-security $zone_id \"$url\" --confirm"
        return 0
    fi

    local actions='[{"id":"disable_security"}]'
    create_rule "$zone_id" --url "$url" --actions "$actions"
}

usage() {
    cat << EOF
Cloudflare Page Rules
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> <zone_id> [options]

Commands:
    list <zone_id>                          List page rules
    get <zone_id> <rule_id>                 Get rule details
    create <zone_id> [options]              Create page rule
    delete <zone_id> <rule_id> [--confirm]  Delete page rule

Quick Rules:
    cache-everything <zone_id> <url> [ttl]  Cache everything for URL
    forwarding <zone_id> <from> <to> [code] Create redirect
    always-https <zone_id> [url]            Force HTTPS
    bypass-cache <zone_id> <url>            Bypass cache
    disable-security <zone_id> <url> --confirm  Disable security

Create Options:
    --url <pattern>        URL pattern (e.g., "*example.com/api/*")
    --actions <json>       Actions JSON array
    --priority <num>       Priority (1 = highest)
    --status <active|disabled>

Common Actions:
    {"id":"always_use_https"}
    {"id":"cache_level","value":"cache_everything"}
    {"id":"cache_level","value":"bypass"}
    {"id":"edge_cache_ttl","value":86400}
    {"id":"browser_cache_ttl","value":3600}
    {"id":"forwarding_url","value":{"url":"https://new.com","status_code":301}}
    {"id":"disable_security"}
    {"id":"ssl","value":"full"}

Examples:
    $(basename "$0") list abc123
    $(basename "$0") cache-everything abc123 "*example.com/static/*" 604800
    $(basename "$0") forwarding abc123 "old.com/*" "https://new.com/\$1"
    $(basename "$0") always-https abc123 "http://*example.com/*"

EOF
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        list)
            list_rules "$@"
            ;;
        get)
            get_rule "$@"
            ;;
        create)
            create_rule "$@"
            ;;
        delete)
            delete_rule "$@"
            ;;
        cache-everything)
            cache_everything "$@"
            ;;
        forwarding)
            forwarding_rule "$@"
            ;;
        always-https)
            always_https "$@"
            ;;
        bypass-cache)
            bypass_cache "$@"
            ;;
        disable-security)
            disable_security "$@"
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
