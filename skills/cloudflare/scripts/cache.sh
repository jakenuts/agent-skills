#!/bin/bash
#
# Cloudflare Cache Management
# Created by After Dark Systems, LLC
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# Purge everything
purge_all() {
    local zone_id="$1"
    local confirm="${2:-}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    if [[ "$confirm" != "--confirm" ]]; then
        echo -e "${YELLOW}Warning: This will purge ALL cached content!${NC}"
        echo "To confirm: $(basename "$0") purge-all $zone_id --confirm"
        return 0
    fi

    echo -e "${BLUE}Purging all cached content...${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/purge_cache" '{"purge_everything":true}')

    if check_response "$response"; then
        echo -e "${GREEN}Cache purged successfully!${NC}"
    else
        return 1
    fi
}

# Purge by URLs
purge_urls() {
    local zone_id="$1"
    shift || true

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: At least one URL required${NC}" >&2
        return 2
    fi

    local urls="["
    local first=true
    for url in "$@"; do
        if [[ "$first" != "true" ]]; then
            urls+=","
        fi
        urls+="\"$url\""
        first=false
    done
    urls+="]"

    echo -e "${BLUE}Purging ${#@} URL(s)...${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/purge_cache" "{\"files\":$urls}")

    if check_response "$response"; then
        echo -e "${GREEN}URLs purged successfully!${NC}"
    else
        return 1
    fi
}

# Purge by cache tags
purge_tags() {
    local zone_id="$1"
    shift || true

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: At least one tag required${NC}" >&2
        return 2
    fi

    local tags="["
    local first=true
    for tag in "$@"; do
        if [[ "$first" != "true" ]]; then
            tags+=","
        fi
        tags+="\"$tag\""
        first=false
    done
    tags+="]"

    echo -e "${BLUE}Purging by tags...${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/purge_cache" "{\"tags\":$tags}")

    if check_response "$response"; then
        echo -e "${GREEN}Cache tags purged successfully!${NC}"
    else
        return 1
    fi
}

# Purge by prefixes
purge_prefixes() {
    local zone_id="$1"
    shift || true

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: At least one prefix required${NC}" >&2
        return 2
    fi

    local prefixes="["
    local first=true
    for prefix in "$@"; do
        if [[ "$first" != "true" ]]; then
            prefixes+=","
        fi
        prefixes+="\"$prefix\""
        first=false
    done
    prefixes+="]"

    echo -e "${BLUE}Purging by prefixes...${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/purge_cache" "{\"prefixes\":$prefixes}")

    if check_response "$response"; then
        echo -e "${GREEN}Prefixes purged successfully!${NC}"
    else
        return 1
    fi
}

# Purge by hosts
purge_hosts() {
    local zone_id="$1"
    shift || true

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error: At least one host required${NC}" >&2
        return 2
    fi

    local hosts="["
    local first=true
    for host in "$@"; do
        if [[ "$first" != "true" ]]; then
            hosts+=","
        fi
        hosts+="\"$host\""
        first=false
    done
    hosts+="]"

    echo -e "${BLUE}Purging by hosts...${NC}"
    local response
    response=$(cf_request "POST" "/zones/$zone_id/purge_cache" "{\"hosts\":$hosts}")

    if check_response "$response"; then
        echo -e "${GREEN}Hosts purged successfully!${NC}"
    else
        return 1
    fi
}

# Get cache level setting
get_cache_level() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings/cache_level")

    if check_response "$response"; then
        echo "Cache Level: $(echo "$response" | jq -r '.result.value')"
    else
        return 1
    fi
}

# Set cache level
set_cache_level() {
    local zone_id="$1"
    local level="$2"

    if [[ -z "$zone_id" || -z "$level" ]]; then
        echo -e "${RED}Error: Zone ID and level required${NC}" >&2
        echo "Levels: bypass, basic, simplified, aggressive, cache_everything"
        return 2
    fi

    echo -e "${BLUE}Setting cache level to: $level${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/cache_level" "{\"value\":\"$level\"}")

    if check_response "$response"; then
        echo -e "${GREEN}Cache level updated!${NC}"
    else
        return 1
    fi
}

# Get browser cache TTL
get_browser_ttl() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/settings/browser_cache_ttl")

    if check_response "$response"; then
        local ttl
        ttl=$(echo "$response" | jq -r '.result.value')
        if [[ "$ttl" == "0" ]]; then
            echo "Browser Cache TTL: Respect Existing Headers"
        else
            echo "Browser Cache TTL: $ttl seconds"
        fi
    else
        return 1
    fi
}

# Set browser cache TTL
set_browser_ttl() {
    local zone_id="$1"
    local ttl="$2"

    if [[ -z "$zone_id" || -z "$ttl" ]]; then
        echo -e "${RED}Error: Zone ID and TTL required${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}Setting browser cache TTL to: $ttl seconds${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/browser_cache_ttl" "{\"value\":$ttl}")

    if check_response "$response"; then
        echo -e "${GREEN}Browser cache TTL updated!${NC}"
    else
        return 1
    fi
}

# Enable/disable development mode
dev_mode() {
    local zone_id="$1"
    local state="$2"

    if [[ -z "$zone_id" || -z "$state" ]]; then
        echo -e "${RED}Error: Zone ID and state (on/off) required${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}Setting development mode: $state${NC}"
    local response
    response=$(cf_request "PATCH" "/zones/$zone_id/settings/development_mode" "{\"value\":\"$state\"}")

    if check_response "$response"; then
        echo -e "${GREEN}Development mode updated!${NC}"
        if [[ "$state" == "on" ]]; then
            echo -e "${YELLOW}Note: Development mode will automatically turn off after 3 hours${NC}"
        fi
    else
        return 1
    fi
}

usage() {
    cat << EOF
Cloudflare Cache Management
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> <zone_id> [options]

Commands:
    purge-all <zone_id> [--confirm]         Purge all cached content
    purge-urls <zone_id> <url> [url...]     Purge specific URLs
    purge-tags <zone_id> <tag> [tag...]     Purge by cache tags
    purge-prefixes <zone_id> <prefix>...    Purge by URL prefixes
    purge-hosts <zone_id> <host> [host...]  Purge by hostnames

    get-level <zone_id>                     Get cache level
    set-level <zone_id> <level>             Set cache level
    get-browser-ttl <zone_id>               Get browser cache TTL
    set-browser-ttl <zone_id> <seconds>     Set browser cache TTL
    dev-mode <zone_id> <on|off>             Toggle development mode

Cache Levels:
    bypass             No caching
    basic              Cache static content
    simplified         Simplified caching
    aggressive         Aggressive caching
    cache_everything   Cache all content

Examples:
    $(basename "$0") purge-all abc123 --confirm
    $(basename "$0") purge-urls abc123 "https://example.com/page" "https://example.com/other"
    $(basename "$0") purge-tags abc123 product-123 category-5
    $(basename "$0") set-level abc123 aggressive
    $(basename "$0") dev-mode abc123 on

EOF
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        purge-all)
            purge_all "$@"
            ;;
        purge-urls)
            purge_urls "$@"
            ;;
        purge-tags)
            purge_tags "$@"
            ;;
        purge-prefixes)
            purge_prefixes "$@"
            ;;
        purge-hosts)
            purge_hosts "$@"
            ;;
        get-level)
            get_cache_level "$@"
            ;;
        set-level)
            set_cache_level "$@"
            ;;
        get-browser-ttl)
            get_browser_ttl "$@"
            ;;
        set-browser-ttl)
            set_browser_ttl "$@"
            ;;
        dev-mode)
            dev_mode "$@"
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
