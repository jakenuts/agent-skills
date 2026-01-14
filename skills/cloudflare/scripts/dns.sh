#!/bin/bash
#
# Cloudflare DNS Management
# Created by After Dark Systems, LLC
#
# Manage DNS records for Cloudflare zones
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# List DNS records
list_records() {
    local zone_id="$1"
    shift || true

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    # Parse optional arguments
    local type_filter="" name_filter="" page="1" per_page="100"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                type_filter="$2"
                shift 2
                ;;
            --name)
                name_filter="$2"
                shift 2
                ;;
            --page)
                page="$2"
                shift 2
                ;;
            --per-page)
                per_page="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    local endpoint="/zones/$zone_id/dns_records?page=$page&per_page=$per_page"

    if [[ -n "$type_filter" ]]; then
        endpoint="${endpoint}&type=$type_filter"
    fi
    if [[ -n "$name_filter" ]]; then
        endpoint="${endpoint}&name=$name_filter"
    fi

    local response
    response=$(cf_request "GET" "$endpoint")

    if check_response "$response"; then
        echo "$response" | jq -r '
            .result[] |
            "[\(.id)] \(.type | ljust(6)) \(.name | ljust(40)) -> \(.content) (TTL: \(.ttl), Proxied: \(.proxied))"
        ' 2>/dev/null || echo "$response" | jq -r '
            .result[] |
            "[\(.id)] \(.type) \(.name) -> \(.content) (TTL: \(.ttl), Proxied: \(.proxied))"
        '

        local count
        count=$(echo "$response" | jq -r '.result_info.count')
        echo ""
        echo -e "${BLUE}Found $count record(s)${NC}"
    else
        return 1
    fi
}

# List DNS records as JSON
list_records_json() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/dns_records?per_page=100")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Get single DNS record
get_record() {
    local zone_id="$1"
    local record_id="$2"

    if [[ -z "$zone_id" || -z "$record_id" ]]; then
        echo -e "${RED}Error: Zone ID and Record ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/dns_records/$record_id")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Create DNS record
create_record() {
    local zone_id="$1"
    shift || true

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    # Parse arguments
    local type="" name="" content="" ttl="1" proxied="false" priority=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                type="$2"
                shift 2
                ;;
            --name)
                name="$2"
                shift 2
                ;;
            --content)
                content="$2"
                shift 2
                ;;
            --ttl)
                ttl="$2"
                shift 2
                ;;
            --proxied)
                proxied="$2"
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

    if [[ -z "$type" || -z "$name" || -z "$content" ]]; then
        echo -e "${RED}Error: --type, --name, and --content are required${NC}" >&2
        return 2
    fi

    local data
    if [[ -n "$priority" ]]; then
        data=$(jq -n \
            --arg type "$type" \
            --arg name "$name" \
            --arg content "$content" \
            --argjson ttl "$ttl" \
            --argjson proxied "$proxied" \
            --argjson priority "$priority" \
            '{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied, priority: $priority}')
    else
        data=$(jq -n \
            --arg type "$type" \
            --arg name "$name" \
            --arg content "$content" \
            --argjson ttl "$ttl" \
            --argjson proxied "$proxied" \
            '{type: $type, name: $name, content: $content, ttl: $ttl, proxied: $proxied}')
    fi

    echo -e "${BLUE}Creating $type record: $name -> $content${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/dns_records" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}DNS record created successfully!${NC}"
        echo "Record ID: $(echo "$response" | jq -r '.result.id')"
        print_result "$response"
    else
        return 1
    fi
}

# Update DNS record
update_record() {
    local zone_id="$1"
    local record_id="$2"
    shift 2 || true

    if [[ -z "$zone_id" || -z "$record_id" ]]; then
        echo -e "${RED}Error: Zone ID and Record ID required${NC}" >&2
        return 2
    fi

    # Parse arguments
    local type="" name="" content="" ttl="" proxied="" priority=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                type="$2"
                shift 2
                ;;
            --name)
                name="$2"
                shift 2
                ;;
            --content)
                content="$2"
                shift 2
                ;;
            --ttl)
                ttl="$2"
                shift 2
                ;;
            --proxied)
                proxied="$2"
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

    # Build update data
    local data="{"
    local first=true

    if [[ -n "$type" ]]; then
        [[ "$first" != "true" ]] && data+=","
        data+="\"type\":\"$type\""
        first=false
    fi
    if [[ -n "$name" ]]; then
        [[ "$first" != "true" ]] && data+=","
        data+="\"name\":\"$name\""
        first=false
    fi
    if [[ -n "$content" ]]; then
        [[ "$first" != "true" ]] && data+=","
        data+="\"content\":\"$content\""
        first=false
    fi
    if [[ -n "$ttl" ]]; then
        [[ "$first" != "true" ]] && data+=","
        data+="\"ttl\":$ttl"
        first=false
    fi
    if [[ -n "$proxied" ]]; then
        [[ "$first" != "true" ]] && data+=","
        data+="\"proxied\":$proxied"
        first=false
    fi
    if [[ -n "$priority" ]]; then
        [[ "$first" != "true" ]] && data+=","
        data+="\"priority\":$priority"
        first=false
    fi

    data+="}"

    echo -e "${BLUE}Updating DNS record: $record_id${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/dns_records/$record_id" "$data")

    if check_response "$response"; then
        echo -e "${GREEN}DNS record updated successfully!${NC}"
        print_result "$response"
    else
        return 1
    fi
}

# Delete DNS record
delete_record() {
    local zone_id="$1"
    local record_id="$2"
    local confirm="${3:-}"

    if [[ -z "$zone_id" || -z "$record_id" ]]; then
        echo -e "${RED}Error: Zone ID and Record ID required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        # Show record details first
        echo -e "${YELLOW}Warning: This will delete the following record:${NC}"
        get_record "$zone_id" "$record_id"
        echo ""
        echo "To confirm, run: $(basename "$0") delete $zone_id $record_id --confirm"
        return 0
    fi

    echo -e "${BLUE}Deleting DNS record: $record_id${NC}"
    local response
    response=$(cf_request "DELETE" "/zones/$zone_id/dns_records/$record_id")

    if check_response "$response"; then
        echo -e "${GREEN}DNS record deleted successfully!${NC}"
    else
        return 1
    fi
}

# Export DNS records
export_records() {
    local zone_id="$1"
    local output_file="${2:-}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}Exporting DNS records...${NC}"

    local response
    response=$(cf_request "GET" "/zones/$zone_id/dns_records/export")

    if [[ -n "$output_file" ]]; then
        echo "$response" > "$output_file"
        echo -e "${GREEN}Records exported to: $output_file${NC}"
    else
        echo "$response"
    fi
}

# Bulk create records from JSON
bulk_create() {
    local zone_id="$1"
    local json_file="$2"

    if [[ -z "$zone_id" || -z "$json_file" ]]; then
        echo -e "${RED}Error: Zone ID and JSON file required${NC}" >&2
        return 2
    fi

    if [[ ! -f "$json_file" ]]; then
        echo -e "${RED}Error: File not found: $json_file${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}Bulk creating DNS records from: $json_file${NC}"

    local records
    records=$(cat "$json_file")

    local count=0
    local errors=0

    echo "$records" | jq -c '.[]' | while read -r record; do
        local response
        response=$(cf_request "POST" "/zones/$zone_id/dns_records" "$record")

        if check_response "$response" 2>/dev/null; then
            local name
            name=$(echo "$record" | jq -r '.name')
            echo -e "${GREEN}Created: $name${NC}"
            ((count++))
        else
            echo -e "${RED}Failed to create record${NC}"
            ((errors++))
        fi
    done

    echo ""
    echo -e "${BLUE}Created $count records, $errors errors${NC}"
}

# Find record by name
find_record() {
    local zone_id="$1"
    local name="$2"

    if [[ -z "$zone_id" || -z "$name" ]]; then
        echo -e "${RED}Error: Zone ID and record name required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/dns_records?name=$name")

    if check_response "$response"; then
        local count
        count=$(echo "$response" | jq -r '.result_info.count')

        if [[ "$count" -eq 0 ]]; then
            echo -e "${YELLOW}No records found for: $name${NC}"
            return 4
        fi

        print_result "$response"
    else
        return 1
    fi
}

# Usage information
usage() {
    cat << EOF
Cloudflare DNS Management
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> <zone_id> [options]

Commands:
    list <zone_id> [--type TYPE] [--name NAME]     List DNS records
    list-json <zone_id>                            List records as JSON
    get <zone_id> <record_id>                      Get single record
    create <zone_id> [options]                     Create DNS record
    update <zone_id> <record_id> [options]         Update DNS record
    delete <zone_id> <record_id> [--confirm]       Delete DNS record
    export <zone_id> [output_file]                 Export records (BIND format)
    find <zone_id> <name>                          Find records by name
    bulk-create <zone_id> <json_file>              Bulk create from JSON

Create/Update Options:
    --type <TYPE>          Record type (A, AAAA, CNAME, MX, TXT, NS, etc.)
    --name <NAME>          Record name (@ for root, or subdomain)
    --content <CONTENT>    Record content (IP, hostname, text, etc.)
    --ttl <TTL>            Time to live (1 = auto, or seconds)
    --proxied <true|false> Enable Cloudflare proxy
    --priority <NUM>       Priority (for MX, SRV records)

Examples:
    # List all A records
    $(basename "$0") list abc123 --type A

    # Create an A record
    $(basename "$0") create abc123 --type A --name www --content 192.0.2.1 --proxied true

    # Create MX record
    $(basename "$0") create abc123 --type MX --name @ --content mail.example.com --priority 10

    # Create TXT record (SPF)
    $(basename "$0") create abc123 --type TXT --name @ --content "v=spf1 include:_spf.google.com ~all"

    # Update record TTL
    $(basename "$0") update abc123 record456 --ttl 3600

    # Delete record
    $(basename "$0") delete abc123 record456 --confirm

EOF
}

# Main
main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        list)
            list_records "$@"
            ;;
        list-json)
            list_records_json "$@"
            ;;
        get)
            get_record "$@"
            ;;
        create)
            create_record "$@"
            ;;
        update)
            update_record "$@"
            ;;
        delete)
            delete_record "$@"
            ;;
        export)
            export_records "$@"
            ;;
        find)
            find_record "$@"
            ;;
        bulk-create)
            bulk_create "$@"
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
