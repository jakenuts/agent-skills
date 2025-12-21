#!/bin/bash
#
# Clean up local branches that have been merged to main/master
#
# Usage:
#   ./cleanup-merged-branches.sh [--dry-run|--force]
#
# Options:
#   --dry-run    Preview what would be deleted
#   --force      Skip confirmation prompts
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# Parse arguments
DRY_RUN=false
FORCE=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --force)
            FORCE=true
            ;;
        *)
            echo -e "${RED}Unknown argument: $arg${NC}"
            echo "Usage: $0 [--dry-run|--force]"
            exit 1
            ;;
    esac
done

# Check if we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Determine main branch (main or master)
MAIN_BRANCH="main"
if ! git rev-parse --verify main > /dev/null 2>&1; then
    if git rev-parse --verify master > /dev/null 2>&1; then
        MAIN_BRANCH="master"
    else
        echo -e "${RED}Error: Neither 'main' nor 'master' branch found${NC}"
        exit 1
    fi
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)

echo ""
echo -e "${CYAN}Clean Up Merged Branches${NC}"
echo ""
echo -e "${GRAY}Main branch: $MAIN_BRANCH${NC}"
echo -e "${GRAY}Current branch: $CURRENT_BRANCH${NC}"

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}Mode: DRY RUN (no changes will be made)${NC}"
fi

echo ""

# Get merged branches (excluding main/master and current branch)
MERGED_BRANCHES=$(git branch --merged "$MAIN_BRANCH" | \
    grep -v "^\*" | \
    grep -v "  $MAIN_BRANCH$" | \
    grep -v "  master$" | \
    grep -v "  main$" | \
    sed 's/^[* ]*//')

if [[ -z "$MERGED_BRANCHES" ]]; then
    echo -e "${GREEN}✓ No merged branches to clean up${NC}"
    exit 0
fi

# Count branches
BRANCH_COUNT=$(echo "$MERGED_BRANCHES" | wc -l | tr -d ' ')

echo "Found $BRANCH_COUNT merged branch(es):"
echo ""
echo "$MERGED_BRANCHES" | sed 's/^/  - /'
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}Dry run complete. Run without --dry-run to delete these branches.${NC}"
    exit 0
fi

# Confirm deletion
if [[ "$FORCE" == false ]]; then
    read -p "Delete these $BRANCH_COUNT branch(es)? (y/N): " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

# Delete branches
echo ""
echo "Deleting branches..."

DELETED_COUNT=0
FAILED_COUNT=0

while IFS= read -r branch; do
    if git branch -d "$branch" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ Deleted: $branch${NC}"
        ((DELETED_COUNT++))
    else
        echo -e "  ${RED}✗ Failed: $branch${NC}"
        ((FAILED_COUNT++))
    fi
done <<< "$MERGED_BRANCHES"

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"
echo "  Deleted: $DELETED_COUNT"
if [[ $FAILED_COUNT -gt 0 ]]; then
    echo -e "  ${YELLOW}Failed: $FAILED_COUNT${NC}"
fi
