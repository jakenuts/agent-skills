#!/bin/bash
#
# Agent Skills Toolkit - Initialization Script
#
# Single entrypoint for setting up the Agent Skills toolkit:
# - Checks prerequisites (.NET SDK)
# - Installs required CLI tools (e.g., logs)
# - Deploys skills to agent platforms (Claude Code, Codex CLI)
# - Validates the installation
#
# Usage:
#   ./init.sh [options]
#
# Options:
#   -t, --target <agent>     Target: claude, codex, or all (default: all)
#   -s, --source <source>    Tool source: local (default), nuget-private, github-packages
#   --skip-tools             Skip tool installation
#   --skip-skills            Skip skill deployment
#   -f, --force              Overwrite existing
#   -d, --dry-run            Preview without changes
#   -h, --help               Show this help

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

# Helpers
step() { echo -e "\n${CYAN}>> $1${NC}"; }
ok() { echo -e "   ${GREEN}OK: $1${NC}"; }
warn() { echo -e "   ${YELLOW}WARN: $1${NC}"; }
err() { echo -e "   ${RED}ERROR: $1${NC}"; }
info() { echo -e "   ${GRAY}$1${NC}"; }
dry() { echo -e "   ${GRAY}[DRY RUN] $1${NC}"; }

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Defaults
TARGET="all"
TOOL_SOURCE="local"
SKIP_TOOLS=false
SKIP_SKILLS=false
FORCE=false
DRY_RUN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            TARGET="$2"
            shift 2
            ;;
        -s|--source)
            TOOL_SOURCE="$2"
            shift 2
            ;;
        --skip-tools)
            SKIP_TOOLS=true
            shift
            ;;
        --skip-skills)
            SKIP_SKILLS=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -t, --target <agent>     Target: claude, codex, or all (default: all)"
            echo "  -s, --source <source>    Tool source: local (default), nuget-private, github-packages"
            echo "  --skip-tools             Skip tool installation"
            echo "  --skip-skills            Skip skill deployment"
            echo "  -f, --force              Overwrite existing"
            echo "  -d, --dry-run            Preview without changes"
            echo "  -h, --help               Show this help"
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Validate target
if [[ ! "$TARGET" =~ ^(claude|codex|all)$ ]]; then
    err "Invalid target: $TARGET. Use: claude, codex, or all"
    exit 1
fi

# Check for jq (for JSON parsing)
if ! command -v jq &> /dev/null; then
    err "jq is required for JSON parsing. Install with: apt-get install jq / brew install jq"
    exit 1
fi

# Load config
if [[ ! -f "$CONFIG_FILE" ]]; then
    err "config.json not found at $CONFIG_FILE"
    exit 1
fi

# Detect OS
OS_TYPE="linux"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="darwin"
fi

# Banner
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Agent Skills Toolkit - Initialization${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${GRAY}Platform: $OS_TYPE${NC}"
echo -e "${GRAY}Tool source: $TOOL_SOURCE${NC}"
echo -e "${GRAY}Target agents: $TARGET${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}Mode: DRY RUN${NC}"
fi
echo ""

# ====================
# Step 1: Prerequisites
# ====================
step "Checking prerequisites..."

# Check .NET SDK (required for dotnet tool install)
DOTNET_VERSION=""
if command -v dotnet &> /dev/null; then
    DOTNET_VERSION=$(dotnet --version 2>/dev/null || true)
fi

if [[ -z "$DOTNET_VERSION" ]]; then
    err ".NET SDK not found. Please install from https://dotnet.microsoft.com/download"
    info "SDK is required for 'dotnet tool install'. Tools will run on .NET 8, 9, or 10 runtimes."
    exit 1
fi

ok ".NET SDK $DOTNET_VERSION"

# Check version
MAJOR_VERSION=$(echo "$DOTNET_VERSION" | cut -d. -f1)
if [[ "$MAJOR_VERSION" -lt 8 ]]; then
    err ".NET SDK $DOTNET_VERSION is too old. Version 8.0+ required."
    info "Tools target .NET 8 with RollForward=LatestMajor (compatible with 8, 9, 10 runtimes)."
    exit 1
fi

info "Tools target .NET 8 (forward-compatible with .NET 9 and 10 runtimes)"

# ====================
# Step 2: Install Tools
# ====================
if [[ "$SKIP_TOOLS" == false ]]; then
    step "Installing CLI tools..."

    # Parse tools from config
    TOOLS=$(jq -r '.tools | keys[]' "$CONFIG_FILE")

    for TOOL_NAME in $TOOLS; do
        PACKAGE_ID=$(jq -r ".tools.\"$TOOL_NAME\".packageId" "$CONFIG_FILE")
        VERSION=$(jq -r ".tools.\"$TOOL_NAME\".version" "$CONFIG_FILE")
        COMMAND=$(jq -r ".tools.\"$TOOL_NAME\".command" "$CONFIG_FILE")

        info "Tool: $TOOL_NAME ($PACKAGE_ID v$VERSION)"

        # Check if already installed
        INSTALLED=""
        if dotnet tool list --global 2>/dev/null | grep -qi "$PACKAGE_ID"; then
            INSTALLED=$(dotnet tool list --global 2>/dev/null | grep -i "$PACKAGE_ID")
        fi

        if [[ -n "$INSTALLED" ]] && [[ "$FORCE" == false ]]; then
            ok "Already installed: $INSTALLED"

            # Verify command works
            if command -v "$COMMAND" &> /dev/null && $COMMAND --help &> /dev/null; then
                ok "Command '$COMMAND' is functional"
            else
                warn "Command '$COMMAND' not responding, consider --force reinstall"
            fi
            continue
        fi

        # Get source config
        SOURCE_TYPE=$(jq -r ".tools.\"$TOOL_NAME\".sources.\"$TOOL_SOURCE\".type" "$CONFIG_FILE")

        if [[ "$SOURCE_TYPE" == "null" ]]; then
            err "Source '$TOOL_SOURCE' not configured for tool '$TOOL_NAME'"
            exit 1
        fi

        # Build install args
        INSTALL_ARGS="tool install --global $PACKAGE_ID --version $VERSION"

        if [[ "$SOURCE_TYPE" == "local" ]]; then
            LOCAL_PATH=$(jq -r ".tools.\"$TOOL_NAME\".sources.\"$TOOL_SOURCE\".path" "$CONFIG_FILE")
            FULL_PATH="$SCRIPT_DIR/$LOCAL_PATH"

            if [[ ! -d "$FULL_PATH" ]]; then
                err "Local tool path not found: $FULL_PATH"
                exit 1
            fi
            INSTALL_ARGS="$INSTALL_ARGS --add-source $FULL_PATH"
        elif [[ "$SOURCE_TYPE" == "nuget" ]]; then
            SOURCE_URL=$(jq -r ".tools.\"$TOOL_NAME\".sources.\"$TOOL_SOURCE\".url" "$CONFIG_FILE")
            INSTALL_ARGS="$INSTALL_ARGS --add-source $SOURCE_URL"
        fi

        # Force reinstall
        if [[ "$FORCE" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                dry "Would uninstall $PACKAGE_ID"
            else
                info "Uninstalling existing $PACKAGE_ID..."
                dotnet tool uninstall --global "$PACKAGE_ID" 2>/dev/null || true
            fi
        fi

        # Install
        if [[ "$DRY_RUN" == true ]]; then
            dry "Would run: dotnet $INSTALL_ARGS"
        else
            info "Installing $PACKAGE_ID..."
            if ! eval "dotnet $INSTALL_ARGS"; then
                err "Failed to install $PACKAGE_ID"
                exit 1
            fi
            ok "Installed $PACKAGE_ID v$VERSION"
        fi

        # Verify command
        if [[ "$DRY_RUN" == false ]]; then
            # Refresh PATH for current session
            export PATH="$HOME/.dotnet/tools:$PATH"

            if command -v "$COMMAND" &> /dev/null && $COMMAND --help &> /dev/null; then
                ok "Command '$COMMAND' is functional"
            else
                warn "Command '$COMMAND' installed but not responding. Restart your terminal."
            fi
        fi

        # Check required environment variables
        REQUIRED_VARS=$(jq -r ".tools.\"$TOOL_NAME\".requiredEnvVars[]? // empty" "$CONFIG_FILE")
        if [[ -n "$REQUIRED_VARS" ]]; then
            info "Checking required environment variables..."
            for VAR in $REQUIRED_VARS; do
                if [[ -n "${!VAR}" ]]; then
                    ok "$VAR is set"
                else
                    warn "$VAR is not set. The tool may not function until this is configured."
                fi
            done
        fi
    done
fi

# ====================
# Step 3: Deploy Skills
# ====================
if [[ "$SKIP_SKILLS" == false ]]; then
    step "Deploying skills..."

    SKILLS_PATH="$SCRIPT_DIR/skills"

    # Find valid skills
    SKILLS=()
    for dir in "$SKILLS_PATH"/*/; do
        if [[ -f "${dir}SKILL.md" ]]; then
            SKILLS+=("$(basename "$dir")")
        fi
    done

    if [[ ${#SKILLS[@]} -eq 0 ]]; then
        warn "No skills found in $SKILLS_PATH"
    else
        info "Found ${#SKILLS[@]} skill(s): ${SKILLS[*]}"
    fi

    # Determine targets
    DEPLOY_TARGETS=()
    if [[ "$TARGET" == "all" ]]; then
        DEPLOY_TARGETS=("claude" "codex")
    else
        DEPLOY_TARGETS=("$TARGET")
    fi

    for AGENT_NAME in "${DEPLOY_TARGETS[@]}"; do
        TARGET_PATH=$(jq -r ".agents.\"$AGENT_NAME\".skillsPath.\"$OS_TYPE\"" "$CONFIG_FILE")
        TARGET_PATH="${TARGET_PATH/#\~/$HOME}"

        info "Deploying to $AGENT_NAME ($TARGET_PATH)..."

        if [[ "$DRY_RUN" == true ]]; then
            dry "Would create directory: $TARGET_PATH"
        else
            if [[ ! -d "$TARGET_PATH" ]]; then
                mkdir -p "$TARGET_PATH"
                ok "Created $TARGET_PATH"
            fi
        fi

        for SKILL in "${SKILLS[@]}"; do
            SKILL_DEST="$TARGET_PATH/$SKILL"

            if [[ -d "$SKILL_DEST" ]] && [[ "$FORCE" == false ]]; then
                info "Skipped $SKILL (exists, use --force to overwrite)"
                continue
            fi

            if [[ "$DRY_RUN" == true ]]; then
                dry "Would copy $SKILL to $TARGET_PATH"
            else
                if [[ -d "$SKILL_DEST" ]]; then
                    rm -rf "$SKILL_DEST"
                fi
                cp -r "$SKILLS_PATH/$SKILL" "$SKILL_DEST"
                ok "Deployed $SKILL"
            fi
        done
    done
fi

# ====================
# Step 4: Validation
# ====================
step "Validating installation..."

VALIDATION_ERRORS=0

# Validate tools
if [[ "$SKIP_TOOLS" == false ]] && [[ "$DRY_RUN" == false ]]; then
    TOOLS=$(jq -r '.tools | keys[]' "$CONFIG_FILE")

    for TOOL_NAME in $TOOLS; do
        COMMAND=$(jq -r ".tools.\"$TOOL_NAME\".command" "$CONFIG_FILE")

        if command -v "$COMMAND" &> /dev/null && $COMMAND --help &> /dev/null; then
            ok "Tool '$COMMAND' responds"
        else
            err "Tool '$COMMAND' not functional"
            ((VALIDATION_ERRORS++))
        fi
    done
fi

# Validate skills
if [[ "$SKIP_SKILLS" == false ]] && [[ "$DRY_RUN" == false ]]; then
    DEPLOY_TARGETS=()
    if [[ "$TARGET" == "all" ]]; then
        DEPLOY_TARGETS=("claude" "codex")
    else
        DEPLOY_TARGETS=("$TARGET")
    fi

    for AGENT_NAME in "${DEPLOY_TARGETS[@]}"; do
        TARGET_PATH=$(jq -r ".agents.\"$AGENT_NAME\".skillsPath.\"$OS_TYPE\"" "$CONFIG_FILE")
        TARGET_PATH="${TARGET_PATH/#\~/$HOME}"

        if [[ -d "$TARGET_PATH" ]]; then
            SKILL_COUNT=$(find "$TARGET_PATH" -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l)
            ok "$AGENT_NAME: $SKILL_COUNT skill(s) deployed"
        else
            warn "$AGENT_NAME: Skills directory not found"
        fi
    done
fi

# ====================
# Summary
# ====================
echo ""
echo -e "${CYAN}========================================${NC}"
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}  Dry run complete - no changes made${NC}"
elif [[ $VALIDATION_ERRORS -gt 0 ]]; then
    echo -e "${YELLOW}  Initialization completed with warnings${NC}"
else
    echo -e "${GREEN}  Initialization complete!${NC}"
fi
echo -e "${CYAN}========================================${NC}"
echo ""

if [[ "$DRY_RUN" == false ]]; then
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "${GRAY}  1. Restart your terminal to ensure PATH updates take effect${NC}"
    echo -e "${GRAY}  2. Set SOLARWINDS_API_TOKEN if not already configured${NC}"
    echo -e "${GRAY}  3. Restart Claude Code or Codex CLI to load skills${NC}"
    echo -e "${GRAY}  4. Test with: logs --help${NC}"
    echo ""
fi

exit $VALIDATION_ERRORS
