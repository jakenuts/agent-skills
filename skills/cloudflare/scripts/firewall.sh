#!/bin/bash
#
# Cloudflare Firewall Rules Management
# Created by After Dark Systems, LLC
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# List firewall rules
list_rules() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/firewall/rules")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "[\(.id)] \(.action | ascii_upcase) - \(.description // "No description") (Priority: \(.priority // "N/A"))"
        '
        local count
        count=$(echo "$response" | jq -r '.result | length')
        echo ""
        echo -e "${BLUE}Found $count rule(s)${NC}"
    else
        return 1
    fi
}

# Get firewall rule
get_rule() {
    local zone_id="$1"
    local rule_id="$2"

    if [[ -z "$zone_id" || -z "$rule_id" ]]; then
        echo -e "${RED}Error: Zone ID and Rule ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/firewall/rules/$rule_id")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Create firewall rule
create_rule() {
    local zone_id="$1"
    shift || true

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local action="" expression="" description="" priority=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --action)
                action="$2"
                shift 2
                ;;
            --expression)
                expression="$2"
                shift 2
                ;;
            --description)
                description="$2"
                shift 2
                ;;
            --priority)
                priority="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$action" || -z "$expression" ]]; then
        echo -e "${RED}Error: --action and --expression are required${NC}" >&2
        return 2
    fi

    local data
    if [[ -n "$priority" ]]; then
        data=$(jq -n \
            --arg action "$action" \
            --arg expression "$expression" \
            --arg description "$description" \
            --argjson priority "$priority" \
            '[{action: $action, filter: {expression: $expression}, description: $description, priority: $priority}]')
    else
        data=$(jq -n \
            --arg action "$action" \
            --arg expression "$expression" \
            --arg description "$description" \
            '[{action: $action, filter: {expression: $expression}, description: $description}]')
    fi

    echo -e "${BLUE}Creating firewall rule...${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/firewall/rules" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}Firewall rule created!${NC}"
        print_result "$response"
    else
        return 1
    fi
}

# Delete firewall rule
delete_rule() {
    local zone_id="$1"
    local rule_id="$2"
    local confirm="${3:-}"

    if [[ -z "$zone_id" || -z "$rule_id" ]]; then
        echo -e "${RED}Error: Zone ID and Rule ID required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        echo -e "${YELLOW}Warning: This will delete the firewall rule!${NC}"
        get_rule "$zone_id" "$rule_id"
        echo ""
        echo "To confirm: $(basename "$0") delete $zone_id $rule_id --confirm"
        return 0
    fi

    local response
    response=$(cf_request "DELETE" "/zones/$zone_id/firewall/rules/$rule_id")

    if check_response "$response"; then
        echo -e "${GREEN}Firewall rule deleted!${NC}"
    else
        return 1
    fi
}

# Quick block IP
block_ip() {
    local zone_id="$1"
    local ip="$2"
    local description="${3:-Blocked by script}"

    if [[ -z "$zone_id" || -z "$ip" ]]; then
        echo -e "${RED}Error: Zone ID and IP required${NC}" >&2
        return 2
    fi

    create_rule "$zone_id" --action block --expression "(ip.src eq $ip)" --description "$description"
}

# Quick allow IP
allow_ip() {
    local zone_id="$1"
    local ip="$2"
    local description="${3:-Allowed by script}"

    if [[ -z "$zone_id" || -z "$ip" ]]; then
        echo -e "${RED}Error: Zone ID and IP required${NC}" >&2
        return 2
    fi

    create_rule "$zone_id" --action allow --expression "(ip.src eq $ip)" --description "$description"
}

# Block country
block_country() {
    local zone_id="$1"
    local country_code="$2"
    local description="${3:-Country blocked}"

    if [[ -z "$zone_id" || -z "$country_code" ]]; then
        echo -e "${RED}Error: Zone ID and country code required${NC}" >&2
        return 2
    fi

    create_rule "$zone_id" --action block --expression "(ip.geoip.country eq \"$country_code\")" --description "$description"
}

usage() {
    cat << EOF
Cloudflare Firewall Rules Management
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> <zone_id> [options]

Commands:
    list <zone_id>                              List firewall rules
    get <zone_id> <rule_id>                     Get rule details
    create <zone_id> [options]                  Create firewall rule
    delete <zone_id> <rule_id> [--confirm]      Delete rule
    block-ip <zone_id> <ip> [description]       Quick block IP
    allow-ip <zone_id> <ip> [description]       Quick allow IP
    block-country <zone_id> <code> [desc]       Block country

Create Options:
    --action <ACTION>       block, challenge, js_challenge, managed_challenge, allow, log, bypass
    --expression <EXPR>     Firewall expression (e.g., "(ip.src eq 1.2.3.4)")
    --description <DESC>    Rule description
    --priority <NUM>        Rule priority

Expression Examples:
    (ip.src eq 192.0.2.1)
    (ip.src in {192.0.2.0/24})
    (ip.geoip.country eq "CN")
    (http.request.uri.path contains "/admin")
    (http.user_agent contains "bot")

Examples:
    $(basename "$0") list abc123
    $(basename "$0") block-ip abc123 192.0.2.100 "Bad actor"
    $(basename "$0") create abc123 --action block --expression "(ip.src eq 1.2.3.4)" --description "Block attacker"

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
        block-ip)
            block_ip "$@"
            ;;
        allow-ip)
            allow_ip "$@"
            ;;
        block-country)
            block_country "$@"
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
