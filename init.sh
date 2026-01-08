#!/bin/bash
#
# Agent Skills Toolkit - Deployment Script
#
# Deploys skill folders to installed agent skill directories.
# Auto-detects Claude Code and Codex CLI installations.
# Skills handle their own dependency installation on first use.
#
# Usage:
#   ./init.sh [--force] [--dry-run]
#

set -e

# Output helpers
step() { echo ""; echo ">> $1"; }
ok() { echo "   OK: $1"; }
warn() { echo "   WARN: $1"; }
err() { echo "   ERROR: $1" >&2; }
info() { echo "   $1"; }
dry() { echo "   [DRY RUN] $1"; }

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_PATH="${SCRIPT_DIR}/skills"

# Options
FORCE=false
DRY_RUN=false

# Target definitions
declare -A TARGET_PATHS
TARGET_PATHS["claude"]="$HOME/.claude/skills"
TARGET_PATHS["codex"]="$HOME/.codex/skills"

declare -A TARGET_NAMES
TARGET_NAMES["claude"]="Claude Code"
TARGET_NAMES["codex"]="Codex CLI"

show_help() {
    echo "Agent Skills Toolkit - Deployment"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -f, --force    Overwrite existing skills"
    echo "  -d, --dry-run  Show what would be deployed"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Deploys skills to all detected agents (Claude Code, Codex CLI)."
}

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

# Validate skills directory
if [[ ! -d "$SKILLS_PATH" ]]; then
    err "Skills directory not found: $SKILLS_PATH"
    exit 1
fi

# Detect installed agents
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

# Find valid skills (directories with SKILL.md)
SKILLS=()
for dir in "$SKILLS_PATH"/*/; do
    if [[ -f "${dir}SKILL.md" ]]; then
        SKILLS+=("$(basename "$dir")")
    fi
done

if [[ ${#SKILLS[@]} -eq 0 ]]; then
    warn "No valid skills found in $SKILLS_PATH"
    exit 0
fi

step "Found ${#SKILLS[@]} skill(s) to deploy"
for skill in "${SKILLS[@]}"; do
    info "- $skill"
done

info ""
info "Detected targets: ${TARGETS[*]}"

# Deploy function
deploy_skill() {
    local skill_name="$1"
    local target_path="$2"
    local skill_source="$SKILLS_PATH/$skill_name"
    local skill_dest="$target_path/$skill_name"

    if [[ -d "$skill_dest" ]]; then
        if [[ "$FORCE" == true ]] || [[ "$DRY_RUN" == true ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                dry "Would overwrite: $skill_name"
            else
                rm -rf "$skill_dest"
                cp -r "$skill_source" "$skill_dest"
                ok "Updated: $skill_name"
            fi
        else
            warn "Skipped (exists): $skill_name - use --force to overwrite"
        fi
    else
        if [[ "$DRY_RUN" == true ]]; then
            dry "Would install: $skill_name"
        else
            cp -r "$skill_source" "$skill_dest"
            ok "Installed: $skill_name"
        fi
    fi
}

# Deploy to each target
for target_key in "${TARGETS[@]}"; do
    target_path="${TARGET_PATHS[$target_key]}"
    target_name="${TARGET_NAMES[$target_key]}"

    step "Deploying to $target_name"
    info "Path: $target_path"

    if [[ "$DRY_RUN" == true ]]; then
        dry "Would create directory: $target_path"
    else
        if [[ ! -d "$target_path" ]]; then
            mkdir -p "$target_path"
            ok "Created directory: $target_path"
        fi
    fi

    for skill in "${SKILLS[@]}"; do
        deploy_skill "$skill" "$target_path"
    done
done

step "Complete"
if [[ "$DRY_RUN" == true ]]; then
    ok "Dry run complete. No changes were made."
else
    ok "Deployment complete. Restart your agent to load new skills."
fi
