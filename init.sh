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
AGENTS_PATH="${SCRIPT_DIR}/agents"

# Options
FORCE=false
DRY_RUN=false

# Target definitions
declare -A SKILLS_TARGET_PATHS
SKILLS_TARGET_PATHS["claude"]="$HOME/.claude/skills"
SKILLS_TARGET_PATHS["codex"]="$HOME/.codex/skills"

declare -A AGENTS_TARGET_PATHS
AGENTS_TARGET_PATHS["claude"]="$HOME/.claude/agents"
AGENTS_TARGET_PATHS["codex"]="$HOME/.codex/agents"

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

# Validate source directories
if [[ ! -d "$SKILLS_PATH" ]]; then
    err "Skills directory not found: $SKILLS_PATH"
    exit 1
fi

HAS_AGENTS=false
if [[ -d "$AGENTS_PATH" ]]; then
    HAS_AGENTS=true
else
    warn "Agents directory not found: $AGENTS_PATH (skipping agents deployment)"
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
fi

# Count agent definition files (*.md in agents folder and subdirectories)
AGENT_COUNT=0
if [[ "$HAS_AGENTS" == true ]]; then
    AGENT_COUNT=$(find "$AGENTS_PATH" -name "*.md" -type f | wc -l)
fi

if [[ ${#SKILLS[@]} -eq 0 ]] && [[ $AGENT_COUNT -eq 0 ]]; then
    warn "No skills or agents found to deploy"
    exit 0
fi

step "Found content to deploy"
if [[ ${#SKILLS[@]} -gt 0 ]]; then
    info "${#SKILLS[@]} skill(s):"
    for skill in "${SKILLS[@]}"; do
        info "  - $skill"
    done
fi
if [[ $AGENT_COUNT -gt 0 ]]; then
    info "$AGENT_COUNT agent definition(s)"
fi

info ""
info "Detected targets: ${TARGETS[*]}"

# Deploy functions
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

deploy_agents() {
    local agents_source="$1"
    local target_path="$2"

    if [[ "$DRY_RUN" == true ]]; then
        dry "Would sync agents directory structure"
        return
    fi

    # Create target directory if needed
    mkdir -p "$target_path"

    # Copy entire agents directory structure, preserving hierarchy
    local deployed=0
    while IFS= read -r -d '' agent_file; do
        # Calculate relative path from agents source
        local relative_path="${agent_file#$agents_source/}"
        local dest_path="$target_path/$relative_path"
        local dest_dir="$(dirname "$dest_path")"

        # Create destination directory if needed
        mkdir -p "$dest_dir"

        # Copy or update the file
        if [[ -f "$dest_path" ]] && [[ "$FORCE" != true ]]; then
            # Skip existing files unless --force is specified
            continue
        fi

        cp "$agent_file" "$dest_path"
        ((++deployed))
    done < <(find "$agents_source" -name "*.md" -type f -print0)

    if [[ $deployed -gt 0 ]]; then
        ok "Deployed $deployed agent definition(s)"
    else
        info "All agent definitions up to date"
    fi
}

# Deploy to each target
for target_key in "${TARGETS[@]}"; do
    skills_target_path="${SKILLS_TARGET_PATHS[$target_key]}"
    agents_target_path="${AGENTS_TARGET_PATHS[$target_key]}"
    target_name="${TARGET_NAMES[$target_key]}"

    step "Deploying to $target_name"

    # Deploy skills
    if [[ ${#SKILLS[@]} -gt 0 ]]; then
        info "Skills path: $skills_target_path"

        if [[ "$DRY_RUN" == true ]]; then
            dry "Would create directory: $skills_target_path"
        else
            if [[ ! -d "$skills_target_path" ]]; then
                mkdir -p "$skills_target_path"
                ok "Created directory: $skills_target_path"
            fi
        fi

        for skill in "${SKILLS[@]}"; do
            deploy_skill "$skill" "$skills_target_path"
        done
    fi

    # Deploy agents
    if [[ "$HAS_AGENTS" == true ]]; then
        info "Agents path: $agents_target_path"
        deploy_agents "$AGENTS_PATH" "$agents_target_path"
    fi
done

step "Complete"
if [[ "$DRY_RUN" == true ]]; then
    ok "Dry run complete. No changes were made."
else
    ok "Deployment complete. Restart your agent to load new skills."
fi
