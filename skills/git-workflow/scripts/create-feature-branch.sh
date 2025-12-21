#!/bin/bash
#
# Create a feature branch with naming conventions
#
# Usage:
#   ./create-feature-branch.sh [feature-name]
#
# If feature-name is not provided, prompts interactively.
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if we're in a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not in a git repository${NC}"
    exit 1
fi

# Get feature name from argument or prompt
FEATURE_NAME="$1"

if [[ -z "$FEATURE_NAME" ]]; then
    echo -e "${CYAN}Create Feature Branch${NC}"
    echo ""
    read -p "Enter feature name (e.g., 'user-authentication'): " FEATURE_NAME
fi

if [[ -z "$FEATURE_NAME" ]]; then
    echo -e "${RED}Error: Feature name is required${NC}"
    exit 1
fi

# Normalize feature name (lowercase, replace spaces with hyphens)
FEATURE_NAME=$(echo "$FEATURE_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

# Create branch name
BRANCH_NAME="feature/$FEATURE_NAME"

# Check if branch already exists
if git rev-parse --verify "$BRANCH_NAME" > /dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Branch '$BRANCH_NAME' already exists${NC}"
    read -p "Switch to it anyway? (y/N): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        git checkout "$BRANCH_NAME"
        exit 0
    else
        exit 1
    fi
fi

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "${YELLOW}Warning: You have uncommitted changes${NC}"
    git status --short
    echo ""
    read -p "Continue anyway? (y/N): " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Determine base branch (main or master)
BASE_BRANCH="main"
if ! git rev-parse --verify main > /dev/null 2>&1; then
    if git rev-parse --verify master > /dev/null 2>&1; then
        BASE_BRANCH="master"
    fi
fi

echo ""
echo -e "${CYAN}Creating feature branch...${NC}"
echo "  Base: $BASE_BRANCH"
echo "  New branch: $BRANCH_NAME"
echo ""

# Offer to update base branch
read -p "Update $BASE_BRANCH from remote first? (Y/n): " response
if [[ ! "$response" =~ ^[Nn]$ ]]; then
    echo "Fetching latest changes..."
    git fetch origin "$BASE_BRANCH"
    git checkout "$BASE_BRANCH"
    git pull origin "$BASE_BRANCH"
fi

# Create and checkout feature branch
git checkout -b "$BRANCH_NAME"

echo ""
echo -e "${GREEN}✓ Feature branch created: $BRANCH_NAME${NC}"
echo ""
echo "Next steps:"
echo "  1. Make your changes"
echo "  2. Commit: git add . && git commit -m 'your message'"
echo "  3. Push: git push -u origin $BRANCH_NAME"
