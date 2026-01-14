#!/bin/bash
#
# Cloudflare API Client
# Created by After Dark Systems, LLC
#
# Core API client with authentication handling for Cloudflare API v4
#

set -e

# Configuration
CF_API_BASE="https://api.cloudflare.com/client/v4"
CF_CREDS_FILE="$HOME/cloudflare_global_key"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load credentials
load_credentials() {
    if [[ ! -f "$CF_CREDS_FILE" ]]; then
        echo -e "${RED}Error: Credentials file not found at $CF_CREDS_FILE${NC}" >&2
        exit 3
    fi

    local file_content
    file_content=$(cat "$CF_CREDS_FILE")

    # Extract the Bearer token (API Token) - look for Bearer followed by token
    CF_API_TOKEN=$(echo "$file_content" | grep -o 'Bearer [A-Za-z0-9_-]*' | head -1 | sed 's/Bearer //' || true)

    # Extract the Global API Key if token not found (37 char hex string on its own line)
    if [[ -z "$CF_API_TOKEN" ]]; then
        CF_GLOBAL_KEY=$(echo "$file_content" | grep -E '^[a-f0-9]{37}$' | head -1 || true)
    fi

    if [[ -z "$CF_API_TOKEN" && -z "$CF_GLOBAL_KEY" ]]; then
        echo -e "${RED}Error: Could not extract API credentials from $CF_CREDS_FILE${NC}" >&2
        exit 3
    fi
}

# Make API request
cf_request() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    load_credentials

    local url="${CF_API_BASE}${endpoint}"
    local curl_args=(-s -X "$method" "$url")

    # Add authentication header
    if [[ -n "$CF_API_TOKEN" ]]; then
        curl_args+=(-H "Authorization: Bearer $CF_API_TOKEN")
    else
        curl_args+=(-H "X-Auth-Key: $CF_GLOBAL_KEY")
        # Note: Would need email for global key auth
    fi

    curl_args+=(-H "Content-Type: application/json")

    if [[ -n "$data" ]]; then
        curl_args+=(-d "$data")
    fi

    local response
    response=$(curl "${curl_args[@]}" 2>/dev/null)

    echo "$response"
}

# Check if response was successful
check_response() {
    local response="$1"
    local success

    success=$(echo "$response" | jq -r '.success' 2>/dev/null)

    if [[ "$success" != "true" ]]; then
        local errors
        errors=$(echo "$response" | jq -r '.errors[] | "[\(.code)] \(.message)"' 2>/dev/null)
        echo -e "${RED}API Error:${NC}" >&2
        echo "$errors" >&2
        return 1
    fi

    return 0
}

# Pretty print JSON response
print_json() {
    local response="$1"
    echo "$response" | jq '.'
}

# Print result only
print_result() {
    local response="$1"
    echo "$response" | jq '.result'
}

# Verify API token
verify_token() {
    echo -e "${BLUE}Verifying API token...${NC}"
    local response
    response=$(cf_request "GET" "/user/tokens/verify")

    if check_response "$response"; then
        echo -e "${GREEN}Token is valid!${NC}"
        echo "$response" | jq '.result'
        return 0
    else
        echo -e "${RED}Token verification failed${NC}"
        return 1
    fi
}

# Get user info
get_user() {
    local response
    response=$(cf_request "GET" "/user")

    if check_response "$response"; then
        print_result "$response"
    else
        return 1
    fi
}

# Usage information
usage() {
    cat << EOF
Cloudflare API Client
Created by After Dark Systems, LLC

Usage: $(basename "$0") <command> [options]

Commands:
    verify-token    Verify the API token is valid
    get-user        Get current user information
    request         Make a raw API request

Raw Request:
    $(basename "$0") request <METHOD> <endpoint> [json_body]

Examples:
    $(basename "$0") verify-token
    $(basename "$0") get-user
    $(basename "$0") request GET /zones
    $(basename "$0") request POST /zones '{"name":"example.com"}'

Environment:
    Credentials are loaded from: $CF_CREDS_FILE

EOF
}

# Main
main() {
    local command="${1:-}"

    case "$command" in
        verify-token)
            verify_token
            ;;
        get-user)
            get_user
            ;;
        request)
            shift
            local method="${1:-GET}"
            local endpoint="${2:-}"
            local data="${3:-}"

            if [[ -z "$endpoint" ]]; then
                echo -e "${RED}Error: Endpoint required${NC}" >&2
                exit 2
            fi

            response=$(cf_request "$method" "$endpoint" "$data")
            if check_response "$response"; then
                print_result "$response"
            else
                exit 1
            fi
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

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
