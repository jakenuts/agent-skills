#!/bin/bash
#
# Cloudflare Analytics
# Created by After Dark Systems, LLC
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/cf-api.sh"

# Get zone analytics dashboard
get_dashboard() {
    local zone_id="$1"
    local since="${2:--1440}"  # Default: last 24 hours (in minutes)
    local until="${3:-0}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/analytics/dashboard?since=$since&until=$until&continuous=true")

    if check_response "$response"; then
        echo -e "${BLUE}Zone Analytics Dashboard${NC}"
        echo "========================"
        echo ""

        echo "$response" | jq -r '
            .result.totals |
            "Requests: \(.requests.all // 0) (Cached: \(.requests.cached // 0))",
            "Bandwidth: \((.bandwidth.all // 0) / 1024 / 1024 | floor)MB (Cached: \((.bandwidth.cached // 0) / 1024 / 1024 | floor)MB)",
            "Unique Visitors: \(.uniques.all // 0)",
            "Threats: \(.threats.all // 0)",
            "",
            "Page Views: \(.pageviews.all // 0)"
        '

        echo ""
        echo -e "${BLUE}HTTP Status Codes:${NC}"
        echo "$response" | jq -r '
            .result.totals.requests |
            if .http_status then
                .http_status | to_entries[] | "  \(.key): \(.value)"
            else
                "  No data available"
            end
        '

        echo ""
        echo -e "${BLUE}Content Types:${NC}"
        echo "$response" | jq -r '
            .result.totals.requests |
            if .content_type then
                .content_type | to_entries | sort_by(-.value) | .[0:5][] | "  \(.key): \(.value)"
            else
                "  No data available"
            end
        '
    else
        return 1
    fi
}

# Get zone analytics as JSON
get_dashboard_json() {
    local zone_id="$1"
    local since="${2:--1440}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/analytics/dashboard?since=$since&continuous=true")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Get DNS analytics
get_dns_analytics() {
    local zone_id="$1"
    local since="${2:--1440}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/dns_analytics/report?since=$since&dimensions=queryName,queryType&metrics=queryCount,responseTime")

    if check_response "$response"; then
        echo -e "${BLUE}DNS Analytics${NC}"
        echo "============="
        print_result "$response"
    else
        return 1
    fi
}

# Get firewall events
get_firewall_events() {
    local zone_id="$1"
    local limit="${2:-25}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/security/events?limit=$limit")

    if check_response "$response"; then
        echo -e "${BLUE}Recent Firewall Events${NC}"
        echo "======================"
        echo "$response" | jq -r '
            .result[] |
            "[\(.datetime)] \(.action) - \(.clientIP) - \(.clientRequestPath // "N/A") (\(.source))"
        '
    else
        return 1
    fi
}

# Get top countries
get_top_countries() {
    local zone_id="$1"
    local since="${2:--1440}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/analytics/dashboard?since=$since&continuous=true")

    if check_response "$response"; then
        echo -e "${BLUE}Top Countries by Requests${NC}"
        echo "========================="
        echo "$response" | jq -r '
            .result.totals.requests.country |
            to_entries | sort_by(-.value) | .[0:10][] |
            "\(.key): \(.value) requests"
        ' 2>/dev/null || echo "No country data available"
    else
        return 1
    fi
}

# Get bandwidth stats
get_bandwidth() {
    local zone_id="$1"
    local since="${2:--1440}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/analytics/dashboard?since=$since&continuous=true")

    if check_response "$response"; then
        echo -e "${BLUE}Bandwidth Statistics${NC}"
        echo "===================="
        echo "$response" | jq -r '
            .result.totals.bandwidth |
            "Total: \((.all // 0) / 1024 / 1024 | floor) MB",
            "Cached: \((.cached // 0) / 1024 / 1024 | floor) MB (\(((.cached // 0) / (.all // 1) * 100) | floor)%)",
            "Uncached: \(((.all // 0) - (.cached // 0)) / 1024 / 1024 | floor) MB",
            "",
            "SSL: \(if .ssl then ((.ssl.encrypted // 0) / 1024 / 1024 | floor) else 0 end) MB encrypted"
        '
    else
        return 1
    fi
}

# Get threats blocked
get_threats() {
    local zone_id="$1"
    local since="${2:--1440}"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    local response
    response=$(cf_request "GET" "/zones/$zone_id/analytics/dashboard?since=$since&continuous=true")

    if check_response "$response"; then
        echo -e "${BLUE}Threats Blocked${NC}"
        echo "==============="
        echo "$response" | jq -r '
            .result.totals.threats |
            "Total Threats: \(.all // 0)",
            "",
            "By Type:",
            if .type then
                .type | to_entries[] | "  \(.key): \(.value)"
            else
                "  No threat type data"
            end,
            "",
            "Top Countries:",
            if .country then
                .country | to_entries | sort_by(-.value) | .[0:5][] | "  \(.key): \(.value)"
            else
                "  No country data"
            end
        '
    else
        return 1
    fi
}

# Quick summary
summary() {
    local zone_id="$1"

    if [[ -z "$zone_id" ]]; then
        echo -e "${RED}Error: Zone ID required${NC}" >&2
        return 2
    fi

    echo -e "${BLUE}=== Zone Analytics Summary (Last 24 Hours) ===${NC}"
    echo ""
    get_dashboard "$zone_id"
}

usage() {
    cat << EOF
Cloudflare Analytics
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> <zone_id> [options]

Commands:
    dashboard <zone_id> [since] [until]     Get analytics dashboard
    dashboard-json <zone_id> [since]        Get dashboard as JSON
    dns <zone_id> [since]                   Get DNS analytics
    firewall-events <zone_id> [limit]       Get firewall events
    top-countries <zone_id> [since]         Get top countries
    bandwidth <zone_id> [since]             Get bandwidth stats
    threats <zone_id> [since]               Get threats blocked
    summary <zone_id>                       Quick summary

Time Parameters:
    since    Minutes ago to start (negative, e.g., -1440 for 24h)
             Or ISO 8601 timestamp
    until    Minutes ago to end (default: 0 = now)

Examples:
    $(basename "$0") summary abc123
    $(basename "$0") dashboard abc123 -10080   # Last 7 days
    $(basename "$0") firewall-events abc123 50
    $(basename "$0") threats abc123

EOF
}

main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        dashboard)
            get_dashboard "$@"
            ;;
        dashboard-json)
            get_dashboard_json "$@"
            ;;
        dns)
            get_dns_analytics "$@"
            ;;
        firewall-events)
            get_firewall_events "$@"
            ;;
        top-countries)
            get_top_countries "$@"
            ;;
        bandwidth)
            get_bandwidth "$@"
            ;;
        threats)
            get_threats "$@"
            ;;
        summary)
            summary "$@"
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
