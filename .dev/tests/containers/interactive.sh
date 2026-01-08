#!/bin/bash
#
# Interactive Container Launcher
#
# Builds and runs a container with an agent CLI, deploys skills,
# and drops you into an interactive shell.
#
# Usage:
#   ./interactive.sh [claude|codex]
#
# Examples:
#   ./interactive.sh claude    # Launch with Claude Code
#   ./interactive.sh codex     # Launch with Codex CLI
#   ./interactive.sh           # Default: Claude Code
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

AGENT="${1:-claude}"

case "$AGENT" in
    claude)
        IMAGE_NAME="agent-skills-claude-code:local"
        DOCKERFILE="$SCRIPT_DIR/images/claude-code/Dockerfile"
        BUILD_CONTEXT="$SCRIPT_DIR/images/claude-code"
        AGENT_CMD="claude"
        SKILLS_DIR="/root/.claude/skills"
        ENV_VAR="ANTHROPIC_API_KEY"
        ;;
    codex)
        IMAGE_NAME="agent-skills-codex-cli:local"
        DOCKERFILE="$SCRIPT_DIR/images/codex-cli/Dockerfile"
        BUILD_CONTEXT="$SCRIPT_DIR/images/codex-cli"
        AGENT_CMD="codex"
        SKILLS_DIR="/root/.codex/skills"
        ENV_VAR="OPENAI_API_KEY"
        ;;
    *)
        echo "Usage: $0 [claude|codex]"
        exit 1
        ;;
esac

echo "=== Interactive Agent Container ==="
echo "Agent: $AGENT_CMD"
echo "Image: $IMAGE_NAME"
echo ""

# Check for API key
API_KEY_VALUE="${!ENV_VAR}"
if [[ -z "$API_KEY_VALUE" ]]; then
    echo "WARNING: $ENV_VAR is not set"
    echo "The agent will not be able to make API calls without it."
    echo ""
    read -p "Continue anyway? (y/N): " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Set $ENV_VAR and try again."
        exit 1
    fi
fi

# Build the image
echo "Building container image..."
docker build -t "$IMAGE_NAME" \
    -f "$DOCKERFILE" \
    --build-arg CLAUDE_CODE_VERSION=latest \
    --build-arg CODEX_VERSION=latest \
    --build-arg DOTNET_CHANNEL=10.0 \
    "$BUILD_CONTEXT"

echo ""
echo "Starting interactive container..."
echo "Skills will be deployed on startup."
echo ""
echo "Once inside, try:"
echo "  $AGENT_CMD --version"
echo "  ls $SKILLS_DIR"
echo "  $AGENT_CMD"
echo ""
echo "Type 'exit' to leave the container."
echo "==========================================="
echo ""

# Run interactively
DOCKER_ARGS=(
    run
    --rm
    -it
    -v "$REPO_ROOT:/opt/agent-skills"
    -w /opt/agent-skills
)

# Add API key if set
if [[ -n "$API_KEY_VALUE" ]]; then
    DOCKER_ARGS+=(-e "$ENV_VAR=$API_KEY_VALUE")
fi

# Add other common env vars if set
[[ -n "$SOLARWINDS_API_TOKEN" ]] && DOCKER_ARGS+=(-e "SOLARWINDS_API_TOKEN=$SOLARWINDS_API_TOKEN")
[[ -n "$WP_SITE_URL" ]] && DOCKER_ARGS+=(-e "WP_SITE_URL=$WP_SITE_URL")
[[ -n "$WP_USERNAME" ]] && DOCKER_ARGS+=(-e "WP_USERNAME=$WP_USERNAME")
[[ -n "$WP_APP_PASSWORD" ]] && DOCKER_ARGS+=(-e "WP_APP_PASSWORD=$WP_APP_PASSWORD")

DOCKER_ARGS+=("$IMAGE_NAME")

# Entry command: deploy skills then start bash
DOCKER_ARGS+=(bash -lc "echo 'Deploying skills...' && ./init.sh --force && echo '' && echo 'Ready! Skills deployed to $SKILLS_DIR' && echo '' && exec bash -l")

MSYS_NO_PATHCONV=1 docker "${DOCKER_ARGS[@]}"
