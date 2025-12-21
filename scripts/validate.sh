#!/bin/bash
#
# Validate Agent Skills for format compliance
#
# Usage:
#   ./validate.sh [skill-name]
#
# Arguments:
#   skill-name  Optional - validate specific skill only

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_PATH="${SCRIPT_DIR}/../skills"

# Counters
ERRORS=0
WARNINGS=0
VALIDATED=0

# Validate skill name format (1-64 chars, lowercase alphanumeric + hyphens)
validate_name() {
    local name="$1"
    if [[ ${#name} -lt 1 ]] || [[ ${#name} -gt 64 ]]; then
        return 1
    fi
    if ! [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]; then
        return 1
    fi
    if [[ "$name" == *--* ]]; then
        return 1
    fi
    return 0
}

# Extract YAML frontmatter value
get_frontmatter() {
    local file="$1"
    local key="$2"

    # Extract value between first two --- markers
    sed -n '/^---$/,/^---$/p' "$file" | grep "^${key}:" | sed "s/^${key}:[[:space:]]*//" | sed 's/^["\x27]\(.*\)["\x27]$/\1/'
}

# Validate a single skill
validate_skill() {
    local skill_dir="$1"
    local skill_name="$(basename "$skill_dir")"
    local local_errors=0
    local local_warnings=0

    echo -e "${YELLOW}Validating: ${skill_name}${NC}"

    # Check SKILL.md exists
    local skill_file="${skill_dir}/SKILL.md"
    if [[ ! -f "$skill_file" ]]; then
        echo -e "  ${RED}ERROR: SKILL.md not found${NC}"
        ((ERRORS++))
        return
    fi

    # Check frontmatter exists
    if ! head -1 "$skill_file" | grep -q '^---$'; then
        echo -e "  ${RED}ERROR: Invalid or missing YAML frontmatter${NC}"
        ((ERRORS++))
        return
    fi

    # Get and validate name
    local name=$(get_frontmatter "$skill_file" "name")
    if [[ -z "$name" ]]; then
        echo -e "  ${RED}ERROR: Missing required field: name${NC}"
        ((local_errors++))
    else
        if ! validate_name "$name"; then
            echo -e "  ${RED}ERROR: Invalid name format: '$name'${NC}"
            ((local_errors++))
        fi
        if [[ "$name" != "$skill_name" ]]; then
            echo -e "  ${YELLOW}WARNING: Skill name '$name' does not match directory name '$skill_name'${NC}"
            ((local_warnings++))
        fi
    fi

    # Get and validate description
    local desc=$(get_frontmatter "$skill_file" "description")
    if [[ -z "$desc" ]]; then
        echo -e "  ${RED}ERROR: Missing required field: description${NC}"
        ((local_errors++))
    elif [[ ${#desc} -gt 1024 ]]; then
        echo -e "  ${RED}ERROR: Description exceeds 1024 characters${NC}"
        ((local_errors++))
    fi

    # Check body content
    local body_lines=$(sed -n '/^---$/,/^---$/d; p' "$skill_file" | grep -v '^[[:space:]]*$' | wc -l)
    if [[ $body_lines -eq 0 ]]; then
        echo -e "  ${YELLOW}WARNING: SKILL.md has no body content${NC}"
        ((local_warnings++))
    fi

    if [[ $local_errors -eq 0 ]] && [[ $local_warnings -eq 0 ]]; then
        echo -e "  ${GREEN}OK${NC}"
    fi

    ((ERRORS += local_errors))
    ((WARNINGS += local_warnings))

    if [[ $local_errors -eq 0 ]]; then
        ((VALIDATED++))
    fi
}

# Main
echo -e "${CYAN}Agent Skills Validator${NC}"
echo -e "${CYAN}=====================${NC}"
echo ""

# Determine skills to validate
if [[ -n "$1" ]]; then
    skill_dir="${SKILLS_PATH}/$1"
    if [[ ! -d "$skill_dir" ]]; then
        echo -e "${RED}Error: Skill not found: $1${NC}"
        exit 1
    fi
    validate_skill "$skill_dir"
else
    for skill_dir in "$SKILLS_PATH"/*/; do
        if [[ -d "$skill_dir" ]]; then
            validate_skill "$skill_dir"
        fi
    done
fi

echo ""
echo -e "${CYAN}Summary${NC}"
echo -e "${CYAN}-------${NC}"
echo "Skills validated: $VALIDATED"

if [[ $ERRORS -gt 0 ]]; then
    echo -e "Errors: ${RED}$ERRORS${NC}"
else
    echo -e "Errors: ${GREEN}$ERRORS${NC}"
fi

if [[ $WARNINGS -gt 0 ]]; then
    echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
else
    echo -e "Warnings: ${GREEN}$WARNINGS${NC}"
fi

[[ $ERRORS -eq 0 ]]
