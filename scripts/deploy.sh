#!/bin/bash
#
# Deploy Agent Skills to Claude Code and/or Codex CLI
#
# Usage:
#   ./deploy.sh <target> [options]
#
# Targets:
#   claude  - Deploy to Claude Code (~/.claude/skills)
#   codex   - Deploy to Codex CLI (~/.codex/skills)
#   all     - Deploy to all platforms
#
# Options:
#   -f, --force    Overwrite existing skills
#   -d, --dry-run  Show what would be deployed
#   -h, --help     Show this help message

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_PATH="${SCRIPT_DIR}/../skills"

# Options
FORCE=false
DRY_RUN=false
TARGET=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 <target> [options]"
            echo ""
            echo "Targets:"
            echo "  claude  - Deploy to Claude Code (~/.claude/skills)"
            echo "  codex   - Deploy to Codex CLI (~/.codex/skills)"
            echo "  all     - Deploy to all platforms"
            echo ""
            echo "Options:"
            echo "  -f, --force    Overwrite existing skills"
            echo "  -d, --dry-run  Show what would be deployed"
            echo "  -h, --help     Show this help message"
            exit 0
            ;;
        claude|codex|all)
            TARGET="$1"
            shift
            ;;
        *)
            echo -e "${RED}Error: Unknown argument: $1${NC}"
            exit 1
            ;;
    esac
done

# Validate target
if [[ -z "$TARGET" ]]; then
    echo -e "${RED}Error: Target required. Use: claude, codex, or all${NC}"
    echo "Run '$0 --help' for usage information."
    exit 1
fi

# Validate skills directory
if [[ ! -d "$SKILLS_PATH" ]]; then
    echo -e "${RED}Error: Skills directory not found: $SKILLS_PATH${NC}"
    exit 1
fi

# Define targets
declare -A TARGET_PATHS
TARGET_PATHS["claude"]="$HOME/.claude/skills"
TARGET_PATHS["codex"]="$HOME/.codex/skills"

declare -A TARGET_NAMES
TARGET_NAMES["claude"]="Claude Code"
TARGET_NAMES["codex"]="Codex CLI"

# Determine deploy targets
DEPLOY_TARGETS=()
if [[ "$TARGET" == "all" ]]; then
    DEPLOY_TARGETS=("claude" "codex")
else
    DEPLOY_TARGETS=("$TARGET")
fi

# Find valid skills (directories with SKILL.md)
SKILLS=()
for dir in "$SKILLS_PATH"/*/; do
    if [[ -f "${dir}SKILL.md" ]]; then
        SKILLS+=("$(basename "$dir")")
    fi
done

if [[ ${#SKILLS[@]} -eq 0 ]]; then
    echo -e "${YELLOW}Warning: No valid skills found in $SKILLS_PATH${NC}"
    exit 0
fi

echo -e "${CYAN}Found ${#SKILLS[@]} skill(s) to deploy:${NC}"
for skill in "${SKILLS[@]}"; do
    echo -e "  ${GRAY}- $skill${NC}"
done
echo ""

# Deploy function
deploy_skill() {
    local skill_name="$1"
    local target_path="$2"
    local skill_source="$SKILLS_PATH/$skill_name"
    local skill_dest="$target_path/$skill_name"

    if [[ -d "$skill_dest" ]]; then
        if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                echo -e "  ${GRAY}[DRY RUN] Would overwrite: $skill_name${NC}"
            else
                rm -rf "$skill_dest"
                cp -r "$skill_source" "$skill_dest"
                echo -e "  ${GREEN}Updated: $skill_name${NC}"
            fi
        else
            echo -e "  ${YELLOW}Skipped (exists): $skill_name - use --force to overwrite${NC}"
        fi
    else
        if [[ "$DRY_RUN" == true ]]; then
            echo -e "  ${GRAY}[DRY RUN] Would copy: $skill_name${NC}"
        else
            cp -r "$skill_source" "$skill_dest"
            echo -e "  ${GREEN}Installed: $skill_name${NC}"
        fi
    fi
}

# Deploy to each target
for target_key in "${DEPLOY_TARGETS[@]}"; do
    target_path="${TARGET_PATHS[$target_key]}"
    target_name="${TARGET_NAMES[$target_key]}"

    echo -e "${YELLOW}Deploying to $target_name ($target_path)...${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${GRAY}[DRY RUN] Would create directory: $target_path${NC}"
    else
        if [[ ! -d "$target_path" ]]; then
            mkdir -p "$target_path"
            echo -e "  ${GREEN}Created directory: $target_path${NC}"
        fi
    fi

    for skill in "${SKILLS[@]}"; do
        deploy_skill "$skill" "$target_path"
    done
    echo ""
done

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${CYAN}Dry run complete. No changes were made.${NC}"
else
    echo -e "${GREEN}Deployment complete!${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  ${GRAY}- Restart Claude Code or Codex CLI to load the new skills${NC}"
    echo -e "  ${GRAY}- Skills will be automatically discovered based on context${NC}"
fi
