#!/bin/bash
set -euo pipefail

CONFIG="${1:-$(dirname "$0")/test-config.json}"
SCENARIO="${SCENARIO:-}"
DRY_RUN="${DRY_RUN:-false}"

info() { echo "INFO: $1"; }
ok() { echo "OK: $1"; }
warn() { echo "WARN: $1"; }
err() { echo "ERROR: $1"; }

if ! command -v docker >/dev/null 2>&1; then
    err "docker is not installed or not on PATH"
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    err "Config not found: $CONFIG"
    info "Copy tests/containers/test-config.example.json to test-config.json and edit it."
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
INIT_PATH="$REPO_ROOT/init.sh"
if [[ ! -f "$INIT_PATH" ]]; then
    err "init.sh not found at $INIT_PATH"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    err "jq is required to parse the config JSON"
    exit 1
fi

SCENARIO_FILTER=""
if [[ -n "$SCENARIO" ]]; then
    SCENARIO_FILTER=" | map(select(.name == \"$SCENARIO\"))"
fi

SCENARIOS_JSON="$(jq -c ".scenarios${SCENARIO_FILTER}" "$CONFIG")"
COUNT="$(echo "$SCENARIOS_JSON" | jq 'length')"
if [[ "$COUNT" -eq 0 ]]; then
    err "No scenarios found in config: $CONFIG"
    exit 1
fi

FAILURES=0

build_image() {
    local scenario_json="$1"
    local image context dockerfile
    image="$(echo "$scenario_json" | jq -r '.image // empty')"
    context="$(echo "$scenario_json" | jq -r '.build.context // empty')"
    dockerfile="$(echo "$scenario_json" | jq -r '.build.dockerfile // "Dockerfile"')"

    if [[ -z "$context" ]]; then
        return 0
    fi

    if [[ -z "$image" ]]; then
        err "Build requested but image name missing"
        return 1
    fi

    local context_path="$REPO_ROOT/$context"
    local dockerfile_path="$context_path/$dockerfile"
    if [[ ! -f "$dockerfile_path" ]]; then
        err "Dockerfile not found: $dockerfile_path"
        return 1
    fi

    local build_args=()
    local args
    args="$(echo "$scenario_json" | jq -r '.build.args // {} | to_entries[] | "\(.key)=\(.value)"')"
    while IFS= read -r arg; do
        if [[ -n "$arg" ]]; then
            build_args+=(--build-arg "$arg")
        fi
    done <<< "$args"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: docker build -t $image -f $dockerfile_path ${build_args[*]} $context_path"
        return 0
    fi

    info "docker build -t $image -f $dockerfile_path ${build_args[*]} $context_path"
    docker build -t "$image" -f "$dockerfile_path" "${build_args[@]}" "$context_path"
}

for i in $(seq 0 $((COUNT - 1))); do
    SCENARIO_JSON="$(echo "$SCENARIOS_JSON" | jq -c ".[$i]")"
    NAME="$(echo "$SCENARIO_JSON" | jq -r '.name // empty')"
    IMAGE="$(echo "$SCENARIO_JSON" | jq -r '.image // empty')"
    AGENT="$(echo "$SCENARIO_JSON" | jq -r '.agent // empty')"

    echo ""
    info "Running scenario: $NAME"

    if [[ -z "$IMAGE" || -z "$AGENT" ]]; then
        err "Missing image or agent for scenario: $NAME"
        FAILURES=$((FAILURES + 1))
        continue
    fi

    REQUIRED_ENV="$(echo "$SCENARIO_JSON" | jq -r '.requiredEnv[]?')"
    for VAR_NAME in $REQUIRED_ENV; do
        if [[ -z "${!VAR_NAME:-}" ]]; then
            err "Missing required env var: $VAR_NAME"
            FAILURES=$((FAILURES + 1))
            continue 2
        fi
    done

    if ! build_image "$SCENARIO_JSON"; then
        FAILURES=$((FAILURES + 1))
        continue
    fi

    if [[ "$AGENT" == "claude" ]]; then
        SKILLS_PATH="~/.claude/skills"
    else
        SKILLS_PATH="~/.codex/skills"
    fi

    CMD_PARTS=(
        "set -e"
        "cd /opt/agent-skills"
        "chmod +x ./init.sh"
        "./init.sh"
        "ls -la $SKILLS_PATH"
    )

    SETUP_CMDS="$(echo "$SCENARIO_JSON" | jq -r '.setupCommands[]?')"
    while IFS= read -r SETUP_CMD; do
        if [[ -n "$SETUP_CMD" ]]; then
            CMD_PARTS+=("$SETUP_CMD")
        fi
    done <<< "$SETUP_CMDS"

    AGENT_CMD="$(echo "$SCENARIO_JSON" | jq -r '.agentCommand // empty')"
    if [[ -n "$AGENT_CMD" ]]; then
        CMD_PARTS+=("$AGENT_CMD")
    fi

    PROMPT_COUNT="$(echo "$SCENARIO_JSON" | jq -r '.prompts | length')"
    if [[ "$PROMPT_COUNT" -gt 0 ]]; then
        for p in $(seq 0 $((PROMPT_COUNT - 1))); do
            PROMPT_CMD="$(echo "$SCENARIO_JSON" | jq -r ".prompts[$p].command // empty")"
            PROMPT_NAME="$(echo "$SCENARIO_JSON" | jq -r ".prompts[$p].name // \"prompt-$p\"")"
            if [[ -n "$PROMPT_CMD" ]]; then
                ENV_EXPORTS=()
                ENV_NAMES="$(echo "$SCENARIO_JSON" | jq -r ".prompts[$p].env[]?")"
                MISSING_ENV=false
                while IFS= read -r ENV_NAME; do
                    if [[ -n "$ENV_NAME" ]]; then
                        if [[ -z "${!ENV_NAME:-}" ]]; then
                            err "Missing required env var for prompt '$PROMPT_NAME': $ENV_NAME"
                            FAILURES=$((FAILURES + 1))
                            MISSING_ENV=true
                            break
                        fi
                        ESCAPED_VALUE="${!ENV_NAME//\'/\'\"\'\"\'}"
                        ENV_EXPORTS+=("export $ENV_NAME='${ESCAPED_VALUE}'")
                    fi
                done <<< "$ENV_NAMES"
                if [[ "$MISSING_ENV" == "true" ]]; then
                    continue 3
                fi
                if [[ "${#ENV_EXPORTS[@]}" -gt 0 ]]; then
                    CMD_PARTS+=("$(IFS=" && "; echo "${ENV_EXPORTS[*]}") && $PROMPT_CMD")
                else
                    CMD_PARTS+=("$PROMPT_CMD")
                fi
            fi
        done
    fi

    CMD="$(IFS=" && "; echo "${CMD_PARTS[*]}")"

    DOCKER_ARGS=(run --rm -v "$REPO_ROOT:/opt/agent-skills" -w /opt/agent-skills)
    for VAR_NAME in $REQUIRED_ENV; do
        DOCKER_ARGS+=(-e "$VAR_NAME=${!VAR_NAME}")
    done

    DOCKER_ARGS+=("$IMAGE" bash -lc "$CMD")

    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: docker run --rm -v <repo>:/opt/agent-skills -w /opt/agent-skills -e <env vars> $IMAGE bash -lc <commands>"
        continue
    fi

    info "docker run --rm -v <repo>:/opt/agent-skills -w /opt/agent-skills -e <env vars> $IMAGE bash -lc <commands>"
    if ! MSYS_NO_PATHCONV=1 docker "${DOCKER_ARGS[@]}"; then
        err "Scenario failed: $NAME"
        FAILURES=$((FAILURES + 1))
    else
        ok "Scenario completed: $NAME"
    fi
done

if [[ "$FAILURES" -gt 0 ]]; then
    err "$FAILURES scenario(s) failed"
    exit 1
fi

ok "All scenarios completed"
