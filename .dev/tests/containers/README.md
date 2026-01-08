# Container Test Harness

This folder contains a lightweight, optional test harness that validates the
Agent Skills toolkit inside containers that have Claude Code and/or Codex CLI
installed and configured. The harness can build local test images, mounts the
repo into a container, runs `init.sh` to deploy skills, then executes agent
commands and prompts you define.

## Prerequisites

- Docker Desktop (Linux containers)
- Container images that include Claude Code or Codex CLI (the harness can build
  local images from the included Dockerfiles)
- API keys available in your host environment:
  - `OPENAI_API_KEY` for Codex CLI
  - `ANTHROPIC_API_KEY` for Claude Code

## Setup

1. Copy the example config and edit it to match your containers:

   ```powershell
   copy .dev\tests\containers\test-config.example.json .dev\tests\containers\test-config.json
   ```

2. Update `.dev/tests/containers/test-config.json`:
   - Set `image` to the container you want to test
   - Optionally set `build` to build a local image from a Dockerfile
   - Set `setupCommands` and `prompts` to your validation commands

## Run (PowerShell)

```powershell
.\.dev\tests\containers\run-tests.ps1
```

## Run (bash)

```bash
./.dev/tests/containers/run-tests.sh
```

## What It Does

For each scenario in the config:

1. Validates required API keys are set on the host.
2. Runs a container with the repo mounted at `/opt/agent-skills`.
3. Executes `./init.sh` to deploy skills to detected agents.
4. Lists the deployed skills directory in the container.
5. Runs setup commands, the agent command, and each prompt command you specify.
   Prompt commands can optionally export per-prompt env vars (for example, to
   set `SOLARWINDS_API_TOKEN` only after the agent asks for it).

## Notes

- The harness does not modify the toolkit itself. It only mounts it into the
  container and runs `init.sh`.
- The included Dockerfiles are based on official install instructions for each
  CLI (from the Codex and Claude Code repositories). No official public Docker
  images were found on Docker Hub during setup, so these images are built locally.
- You are responsible for choosing valid agent CLI commands for each container.
