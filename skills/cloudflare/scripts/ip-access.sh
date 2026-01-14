#!/bin/bash
#
# Cloudflare IP Access Rules Management
# Created by After Dark Systems, LLC
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# List access rules
list_rules() {
    local zone_id="$1"
    local page="${2:-1}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/firewall/access_rules/rules?page=$page&per_page=50")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "[\(.id)] \(.mode | ascii_upcase) \(.configuration.target): \(.configuration.value) - \(.notes // "No notes")"
        '
    else
        return 1
    fi
}

# Create access rule
create_rule() {
    local zone_id="$1"
    local mode="$2"
    local target="$3"
    local value="$4"
    local notes="${5:-}"

    if [[ -z "$zone_id" || -z "$mode" || -z "$target" || -z "$value" ]]; then
        echo -e "${RED}Error: Zone ID, mode, target, and value required${NC}" >&2
        return 2
    fi

    local data
    data=$(jq -n \
        --arg mode "$mode" \
        --arg target "$target" \
        --arg value "$value" \
        --arg notes "$notes" \
        '{mode: $mode, configuration: {target: $target, value: $value}, notes: $notes}')

    local response
    response=$(cf_request "POST" "/zones/$zone_id/firewall/access_rules/rules" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}Access rule created!${NC}"
        print_result "$response"
    else
        return 1
    fi
}

# Block IP
block() {
    local zone_id="$1"
    local value="$2"
    local notes="${3:-Blocked}"

    if [[ -z "$zone_id" || -z "$value" ]]; then
        echo -e "${RED}Error: Zone ID and IP/range required${NC}" >&2
        return 2
    fi

    local target="ip"
    if [[ "$value" == *"/"* ]]; then
        target="ip_range"
    elif [[ "$value" == "AS"* ]]; then
        target="asn"
    elif [[ ${#value} -eq 2 ]]; then
        target="country"
    fi

    echo -e "${BLUE}Blocking $target: $value${NC}"
    create_rule "$zone_id" "block" "$target" "$value" "$notes"
}

# Allow/Whitelist IP
allow() {
    local zone_id="$1"
    local value="$2"
    local notes="${3:-Allowed}"

    if [[ -z "$zone_id" || -z "$value" ]]; then
        echo -e "${RED}Error: Zone ID and IP/range required${NC}" >&2
        return 2
    fi

    local target="ip"
    if [[ "$value" == *"/"* ]]; then
        target="ip_range"
    elif [[ "$value" == "AS"* ]]; then
        target="asn"
    elif [[ ${#value} -eq 2 ]]; then
        target="country"
    fi

    echo -e "${BLUE}Allowing $target: $value${NC}"
    create_rule "$zone_id" "whitelist" "$target" "$value" "$notes"
}

# Challenge IP
challenge() {
    local zone_id="$1"
    local value="$2"
    local notes="${3:-Challenged}"

    if [[ -z "$zone_id" || -z "$value" ]]; then
        echo -e "${RED}Error: Zone ID and IP/range required${NC}" >&2
        return 2
    fi

    local target="ip"
    if [[ "$value" == *"/"* ]]; then
        target="ip_range"
    fi

    echo -e "${BLUE}Challenging $target: $value${NC}"
    create_rule "$zone_id" "challenge" "$target" "$value" "$notes"
}

# Delete access rule
delete_rule() {
    local zone_id="$1"
    local rule_id="$2"
    local confirm="${3:-}"

    if [[ -z "$zone_id" || -z "$rule_id" ]]; then
        echo -e "${RED}Error: Zone ID and Rule ID required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        echo -e "${YELLOW}To confirm: $(basename "$0") delete $zone_id $rule_id --confirm${NC}"
        return 0
    fi

    local response
    response=$(cf_request "DELETE" "/zones/$zone_id/firewall/access_rules/rules/$rule_id")

    if check_response "$response"; then
        echo -e "${GREEN}Access rule deleted!${NC}"
    else
        return 1
    fi
}

usage() {
    cat << EOF
Cloudflare IP Access Rules
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> <zone_id> [options]

Commands:
    list <zone_id>                          List access rules
    block <zone_id> <ip|range|asn|country> [notes]   Block
    allow <zone_id> <ip|range|asn|country> [notes]   Whitelist
    challenge <zone_id> <ip|range> [notes]  Challenge
    delete <zone_id> <rule_id> [--confirm]  Delete rule

Value Types (auto-detected):
    192.0.2.1         Single IP
    192.0.2.0/24      IP range (CIDR)
    AS12345           ASN
    US                Country code (2 letters)

Examples:
    $(basename "$0") block abc123 192.0.2.100 "Malicious IP"
    $(basename "$0") allow abc123 10.0.0.0/8 "Internal network"
    $(basename "$0") block abc123 CN "Block country"
    $(basename "$0") challenge abc123 AS12345 "Suspicious ASN"

EOF
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        list)
            list_rules "$@"
            ;;
        block)
            block "$@"
            ;;
        allow|whitelist)
            allow "$@"
            ;;
        challenge)
            challenge "$@"
            ;;
        delete)
            delete_rule "$@"
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
