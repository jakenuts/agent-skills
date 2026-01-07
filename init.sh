#!/bin/bash
#
# Agent Skills Toolkit - Deployment Script
#
# Deploys skill folders to installed agent skill directories.
# No dependency installation; skills handle setup on activation.
#
# Usage:
#   ./init.sh [--force] [--dry-run]
#

set -e

step() { echo ""; echo ">> $1"; }
ok() { echo "   OK: $1"; }
warn() { echo "   WARN: $1"; }
err() { echo "   ERROR: $1" >&2; }
info() { echo "   $1"; }
dry() { echo "   [DRY RUN] $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/scripts/deploy.sh"

FORCE=false
DRY_RUN=false

show_help() {
    echo "Agent Skills Toolkit - Deployment"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -f, --force    Overwrite existing skills"
    echo "  -d, --dry-run  Show what would be deployed"
    echo "  -h, --help     Show this help message"
}

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
            show_help
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            show_help
            exit 1
            ;;
    esac
done

if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    err "Deploy script not found: $DEPLOY_SCRIPT"
    exit 1
fi

TARGETS=()
if command -v claude >/dev/null 2>&1 || [[ -d "$HOME/.claude" ]]; then
    TARGETS+=("claude")
fi
if command -v codex >/dev/null 2>&1 || [[ -d "$HOME/.codex" ]]; then
    TARGETS+=("codex")
fi

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    warn "No supported agents detected."
    info "Expected commands: claude, codex"
    info "Expected directories: $HOME/.claude or $HOME/.codex"
    exit 1
fi

step "Deploying skills"
info "Detected targets: ${TARGETS[*]}"

DEPLOY_ARGS=()
if [[ "$FORCE" == true ]]; then
    DEPLOY_ARGS+=("--force")
fi
if [[ "$DRY_RUN" == true ]]; then
    DEPLOY_ARGS+=("--dry-run")
fi

for target in "${TARGETS[@]}"; do
    if [[ "$DRY_RUN" == true ]]; then
        dry "bash $DEPLOY_SCRIPT $target ${DEPLOY_ARGS[*]}"
    fi
    bash "$DEPLOY_SCRIPT" "$target" "${DEPLOY_ARGS[@]}"
done

if [[ "$DRY_RUN" == true ]]; then
    ok "Dry run complete. No changes were made."
else
    ok "Deployment complete. Restart your agent to load new skills."
fi
