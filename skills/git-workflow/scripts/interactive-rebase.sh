#!/bin/bash
#
# Interactive rebase helper with simplified options
#
# Usage:
#   ./interactive-rebase.sh <commit-count|ref>
#
# Examples:
#   ./interactive-rebase.sh 3          # Rebase last 3 commits
#   ./interactive-rebase.sh abc123     # Rebase since commit abc123
#   ./interactive-rebase.sh main       # Rebase onto main
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

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "${RED}Error: You have uncommitted changes${NC}"
    echo ""
    echo "Please commit or stash your changes before rebasing:"
    echo "  git stash"
    echo "  # or"
    echo "  git add . && git commit -m 'WIP'"
    exit 1
fi

# Get argument
TARGET="$1"

if [[ -z "$TARGET" ]]; then
    echo -e "${RED}Error: Target required${NC}"
    echo ""
    echo "Usage: $0 <commit-count|ref>"
    echo ""
    echo "Examples:"
    echo "  $0 3          # Rebase last 3 commits"
    echo "  $0 abc123     # Rebase since commit abc123"
    echo "  $0 main       # Rebase onto main"
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)

echo ""
echo -e "${CYAN}Interactive Rebase${NC}"
echo ""
echo -e "Current branch: $CURRENT_BRANCH"

# Determine rebase target
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    # Numeric - rebase last N commits
    REBASE_CMD="git rebase -i HEAD~$TARGET"
    echo -e "Action: Rebase last $TARGET commits"
elif git rev-parse --verify "$TARGET" > /dev/null 2>&1; then
    # Git ref exists - rebase onto it
    REBASE_CMD="git rebase -i $TARGET"
    echo -e "Action: Rebase onto $TARGET"
else
    echo -e "${RED}Error: Invalid target '$TARGET'${NC}"
    echo "Must be a number or a valid git reference (commit hash, branch name, etc.)"
    exit 1
fi

echo ""
echo -e "${YELLOW}Interactive Rebase Quick Reference:${NC}"
echo ""
echo "  pick   (p) - Use commit as-is"
echo "  reword (r) - Use commit, but edit message"
echo "  edit   (e) - Use commit, but stop to amend"
echo "  squash (s) - Meld into previous commit"
echo "  fixup  (f) - Like squash, but discard message"
echo "  drop   (d) - Remove commit"
echo ""
echo "Common workflow:"
echo "  1. Change 'pick' to desired action for each commit"
echo "  2. Save and close the editor"
echo "  3. Follow any additional prompts"
echo ""

read -p "Continue with interactive rebase? (y/N): " response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Launching interactive rebase..."
echo ""

# Run the rebase
if eval "$REBASE_CMD"; then
    echo ""
    echo -e "${GREEN}✓ Rebase complete!${NC}"
    echo ""
    echo "To push changes (if branch was already pushed):"
    echo "  git push --force-with-lease origin $CURRENT_BRANCH"
else
    echo ""
    echo -e "${RED}Rebase encountered issues${NC}"
    echo ""
    echo "To abort the rebase:"
    echo "  git rebase --abort"
    echo ""
    echo "To continue after resolving conflicts:"
    echo "  git add <resolved-files>"
    echo "  git rebase --continue"
    exit 1
fi
