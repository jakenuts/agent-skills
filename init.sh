#!/bin/bash
#
# Agent Skills Toolkit - Initialization Script (Refactored)
#
# Single entrypoint for setting up the Agent Skills toolkit with lazy installation:
# - Lightweight deployment: Deploy skills immediately (just markdown files)
# - Deferred tool installation: Only install tools when actually needed
# - Shared prerequisites: .NET SDK check happens once, benefits all tools
# - Agent-driven setup: Skills guide agents through prerequisite installation
#
# Usage:
#   ./init.sh [options]
#
# Common Usage:
#   ./init.sh --deploy-only              # Fast: deploy all skills, no tool installation
#   ./init.sh --install-tool <name>      # Install specific tool when needed
#   ./init.sh                            # Legacy: deploy skills + install all tools
#
# Options:
#   -t, --target <agent>         Target: claude, codex, or all (default: all)
#   -s, --source <source>        Tool source: local (default), nuget-private, github-packages
#   --deploy-only                Deploy skills only, skip all tool installation
#   --install-tool <name>        Install specific tool (e.g., solarwinds-logs)
#   --check-prerequisites        Check prerequisites only, don't install anything
#   --skip-tools                 Skip tool installation (alias for --deploy-only)
#   --skip-skills                Skip skill deployment
#   -f, --force                  Overwrite existing installations
#   -d, --dry-run                Preview without changes
#   -h, --help                   Show this help

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
ok() { echo -e "   ${GREEN}✓ $1${NC}"; }
warn() { echo -e "   ${YELLOW}⚠️  $1${NC}"; }
err() { echo -e "   ${RED}✗ $1${NC}"; }
info() { echo -e "   ${GRAY}$1${NC}"; }
dry() { echo -e "   ${GRAY}[DRY RUN] $1${NC}"; }

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Source helper scripts
source "$SCRIPT_DIR/scripts/install-prerequisites.sh"
source "$SCRIPT_DIR/scripts/setup-env.sh"

# Defaults
TARGET="all"
TOOL_SOURCE="local"
SKIP_TOOLS=false
SKIP_SKILLS=false
DEPLOY_ONLY=false
INSTALL_TOOL=""
CHECK_PREREQUISITES_ONLY=false
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
        --deploy-only|--skip-tools)
            DEPLOY_ONLY=true
            SKIP_TOOLS=true
            shift
            ;;
        --install-tool)
            INSTALL_TOOL="$2"
            shift 2
            ;;
        --check-prerequisites)
            CHECK_PREREQUISITES_ONLY=true
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
            echo "Agent Skills Toolkit - Initialization Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Common Usage:"
            echo "  $0 --deploy-only              # Fast: deploy skills, no tool installation"
            echo "  $0 --install-tool <name>      # Install specific tool when needed"
            echo "  $0                            # Legacy: deploy skills + install all tools"
            echo ""
            echo "Options:"
            echo "  -t, --target <agent>         Target: claude, codex, or all (default: all)"
            echo "  -s, --source <source>        Tool source: local, nuget-private, github-packages"
            echo "  --deploy-only                Deploy skills only, skip tool installation"
            echo "  --install-tool <name>        Install specific tool (e.g., solarwinds-logs)"
            echo "  --check-prerequisites        Check prerequisites only"
            echo "  --skip-tools                 Alias for --deploy-only"
            echo "  --skip-skills                Skip skill deployment"
            echo "  -f, --force                  Overwrite existing installations"
            echo "  -d, --dry-run                Preview without changes"
            echo "  -h, --help                   Show this help"
            echo ""
            echo "Examples:"
            echo "  # Container startup - fast deployment, no tool installation"
            echo "  ./init.sh --deploy-only"
            echo ""
            echo "  # Agent activates solarwinds-logs skill"
            echo "  ./init.sh --install-tool solarwinds-logs"
            echo ""
            echo "  # Check if .NET SDK is installed"
            echo "  ./init.sh --check-prerequisites"
            echo ""
            echo "  # Full installation (legacy mode)"
            echo "  ./init.sh"
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            echo "Run '$0 --help' for usage information."
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
echo -e "${CYAN}  Agent Skills Toolkit - Init (v2.0)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${GRAY}Platform: $OS_TYPE${NC}"
echo -e "${GRAY}Tool source: $TOOL_SOURCE${NC}"
echo -e "${GRAY}Target agents: $TARGET${NC}"
if [[ "$DEPLOY_ONLY" == true ]]; then
    echo -e "${GRAY}Mode: Deploy skills only (lazy installation)${NC}"
elif [[ -n "$INSTALL_TOOL" ]]; then
    echo -e "${GRAY}Mode: Install tool '$INSTALL_TOOL'${NC}"
elif [[ "$CHECK_PREREQUISITES_ONLY" == true ]]; then
    echo -e "${GRAY}Mode: Check prerequisites only${NC}"
fi
if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}Dry run: No changes will be made${NC}"
fi
echo ""

# ====================
# Mode: Check Prerequisites Only
# ====================
if [[ "$CHECK_PREREQUISITES_ONLY" == true ]]; then
    step "Checking prerequisites..."

    if check_dotnet_sdk 10; then
        ok "All prerequisites met"
        exit 0
    else
        warn ".NET SDK 10.0+ not found"
        install_dotnet_sdk_guide 10
        exit 1
    fi
fi

# ====================
# Mode: Install Specific Tool
# ====================
if [[ -n "$INSTALL_TOOL" ]]; then
    step "Installing tool: $INSTALL_TOOL"

    # Verify tool exists in config
    TOOL_EXISTS=$(jq -r ".tools.\"$INSTALL_TOOL\" // empty" "$CONFIG_FILE")
    if [[ -z "$TOOL_EXISTS" ]]; then
        err "Tool '$INSTALL_TOOL' not found in config.json"
        echo ""
        echo "Available tools:"
        jq -r '.tools | keys[]' "$CONFIG_FILE" | sed 's/^/  - /'
        exit 1
    fi

    # Check .NET SDK prerequisite
    if ! check_dotnet_sdk 10; then
        err ".NET SDK 10.0+ is required to install this tool"
        install_dotnet_sdk_guide 10
        exit 1
    fi

    # Get tool details
    PACKAGE_ID=$(jq -r ".tools.\"$INSTALL_TOOL\".packageId" "$CONFIG_FILE")
    VERSION=$(jq -r ".tools.\"$INSTALL_TOOL\".version" "$CONFIG_FILE")
    COMMAND=$(jq -r ".tools.\"$INSTALL_TOOL\".command" "$CONFIG_FILE")

    # Get source configuration
    SOURCE_TYPE=$(jq -r ".tools.\"$INSTALL_TOOL\".sources.\"$TOOL_SOURCE\".type // \"local\"" "$CONFIG_FILE")

    if [[ "$SOURCE_TYPE" == "local" ]]; then
        SOURCE_PATH=$(jq -r ".tools.\"$INSTALL_TOOL\".sources.\"$TOOL_SOURCE\".path" "$CONFIG_FILE")
        SOURCE_PATH="$SCRIPT_DIR/$SOURCE_PATH"
    else
        SOURCE_PATH=$(jq -r ".tools.\"$INSTALL_TOOL\".sources.\"$TOOL_SOURCE\".url" "$CONFIG_FILE")
    fi

    info "Package: $PACKAGE_ID v$VERSION"
    info "Source: $SOURCE_PATH"

    # Check if already installed
    if check_dotnet_tool "$PACKAGE_ID" && [[ "$FORCE" == false ]]; then
        # Verify command works
        if command -v "$COMMAND" &> /dev/null && $COMMAND --help &> /dev/null 2>&1; then
            ok "Tool is already installed and functional"

            # Check environment variables
            REQUIRED_VARS=$(jq -r ".tools.\"$INSTALL_TOOL\".requiredEnvVars[]? // empty" "$CONFIG_FILE")
            if [[ -n "$REQUIRED_VARS" ]]; then
                echo ""
                step "Checking required environment variables..."
                ALL_SET=true
                for VAR_NAME in $REQUIRED_VARS; do
                    if ! check_env_var "$VAR_NAME"; then
                        warn "$VAR_NAME is not set"
                        ALL_SET=false
                    fi
                done

                if [[ "$ALL_SET" == false ]]; then
                    echo ""
                    warn "Some environment variables are missing"
                    echo ""
                    echo "The tool is installed but may not work without these variables."
                    echo "See the skill documentation for setup instructions."
                fi
            fi

            exit 0
        else
            warn "Command '$COMMAND' not responding, reinstalling..."
            uninstall_dotnet_tool "$PACKAGE_ID"
        fi
    elif [[ "$FORCE" == true ]] && check_dotnet_tool "$PACKAGE_ID"; then
        info "Force reinstall requested, uninstalling existing version..."
        uninstall_dotnet_tool "$PACKAGE_ID"
    fi

    # Install the tool
    if [[ "$DRY_RUN" == true ]]; then
        dry "Would install: $PACKAGE_ID v$VERSION from $SOURCE_PATH"
    else
        if [[ "$SOURCE_TYPE" == "local" ]]; then
            install_dotnet_tool_local "$PACKAGE_ID" "$VERSION" "$SOURCE_PATH"
        else
            # For remote sources, use the URL directly
            info "Installing from remote source: $SOURCE_PATH"
            dotnet tool install --global "$PACKAGE_ID" --version "$VERSION" --add-source "$SOURCE_PATH"
        fi

        # Verify installation
        if command -v "$COMMAND" &> /dev/null && $COMMAND --help &> /dev/null 2>&1; then
            ok "Tool installed and verified: $COMMAND"
        else
            err "Tool installed but command '$COMMAND' not responding"
            echo ""
            echo "You may need to add the .NET tools directory to your PATH:"
            echo "  export PATH=\"\$HOME/.dotnet/tools:\$PATH\""
            exit 1
        fi

        # Check environment variables
        REQUIRED_VARS=$(jq -r ".tools.\"$INSTALL_TOOL\".requiredEnvVars[]? // empty" "$CONFIG_FILE")
        if [[ -n "$REQUIRED_VARS" ]]; then
            echo ""
            step "Checking required environment variables..."

            for VAR_NAME in $REQUIRED_VARS; do
                if ! check_env_var "$VAR_NAME"; then
                    warn "$VAR_NAME is not set"
                    show_env_var_guide "$VAR_NAME" "$INSTALL_TOOL configuration"
                fi
            done
        fi
    fi

    echo ""
    ok "Tool installation complete!"
    echo ""
    echo "Next steps:"
    echo "  - Configure required environment variables (if needed)"
    echo "  - Test the tool: $COMMAND --help"
    exit 0
fi

# ====================
# Step 1: Deploy Skills
# ====================
if [[ "$SKIP_SKILLS" == false ]]; then
    step "Deploying skills to agent platforms..."

    # Determine deploy targets
    DEPLOY_TARGETS=()
    if [[ "$TARGET" == "all" ]]; then
        DEPLOY_TARGETS=("claude" "codex")
    else
        DEPLOY_TARGETS=("$TARGET")
    fi

    # Get agent paths from config
    declare -A TARGET_PATHS
    for target_key in "${DEPLOY_TARGETS[@]}"; do
        target_path=$(jq -r ".agents.\"$target_key\".skillsPath.$OS_TYPE" "$CONFIG_FILE")
        # Expand ~ to $HOME
        target_path="${target_path/#\~/$HOME}"
        TARGET_PATHS[$target_key]="$target_path"
    done

    # Find valid skills
    SKILLS=()
    for dir in "$SCRIPT_DIR"/skills/*/; do
        if [[ -f "${dir}SKILL.md" ]]; then
            SKILLS+=("$(basename "$dir")")
        fi
    done

    if [[ ${#SKILLS[@]} -eq 0 ]]; then
        warn "No valid skills found in $SCRIPT_DIR/skills/"
    else
        info "Found ${#SKILLS[@]} skill(s): ${SKILLS[*]}"

        # Deploy to each target
        for target_key in "${DEPLOY_TARGETS[@]}"; do
            target_path="${TARGET_PATHS[$target_key]}"

            info "Deploying to $target_key ($target_path)..."

            if [[ "$DRY_RUN" == true ]]; then
                dry "Would create directory: $target_path"
            else
                mkdir -p "$target_path"
            fi

            for skill in "${SKILLS[@]}"; do
                skill_source="$SCRIPT_DIR/skills/$skill"
                skill_dest="$target_path/$skill"

                if [[ -d "$skill_dest" ]] && [[ "$FORCE" == false ]]; then
                    info "  $skill (already exists, use --force to overwrite)"
                elif [[ "$DRY_RUN" == true ]]; then
                    dry "  Would deploy: $skill"
                else
                    rm -rf "$skill_dest"
                    cp -r "$skill_source" "$skill_dest"
                    ok "  $skill"
                fi
            done
        done
    fi

    echo ""
    ok "Skill deployment complete!"
fi

# ====================
# Step 2: Install Tools (Legacy Mode or Explicit)
# ====================
if [[ "$SKIP_TOOLS" == false ]] && [[ "$DEPLOY_ONLY" == false ]]; then
    echo ""
    step "Installing CLI tools (legacy mode)..."

    # Check .NET SDK
    if ! check_dotnet_sdk 10; then
        err ".NET SDK 10.0+ is required to install tools"
        install_dotnet_sdk_guide 10
        echo ""
        warn "Skipping tool installation - use './init.sh --install-tool <name>' when ready"
        exit 0
    fi

    # Get all tools
    TOOLS=$(jq -r '.tools | keys[]' "$CONFIG_FILE")

    for TOOL_NAME in $TOOLS; do
        echo ""
        info "Installing tool: $TOOL_NAME"

        # Use the --install-tool logic
        if [[ "$DRY_RUN" == true ]]; then
            dry "Would run: ./init.sh --install-tool $TOOL_NAME"
        else
            # Call ourselves recursively for each tool
            "$0" --install-tool "$TOOL_NAME" --source "$TOOL_SOURCE" $([ "$FORCE" == true ] && echo "--force")
        fi
    done
fi

# ====================
# Final Message
# ====================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Initialization Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [[ "$DEPLOY_ONLY" == true ]]; then
    echo -e "${CYAN}Skills deployed successfully (lazy installation mode)${NC}"
    echo ""
    echo "Tools will be installed on-demand when skills are activated."
    echo ""
    echo "To install a specific tool:"
    echo "  ./init.sh --install-tool <tool-name>"
    echo ""
    echo "Available tools:"
    jq -r '.tools | keys[]' "$CONFIG_FILE" | sed 's/^/  - /'
elif [[ "$SKIP_SKILLS" == false ]]; then
    echo -e "${CYAN}Next steps:${NC}"
    echo "  - Restart your agent (Claude Code, Codex CLI, etc.)"
    echo "  - Skills will be automatically discovered based on context"
    if [[ "$SKIP_TOOLS" == false ]]; then
        echo "  - Test installed tools: <command> --help"
    fi
fi

echo ""
