# Agent Skills Toolkit

A unified collection of Agent Skills compatible with both **Claude Code** and **OpenAI Codex CLI**. Skills are modular capabilities that extend AI agents with specialized knowledge and workflows.

## Overview

This toolkit provides reusable skills that follow the [Agent Skills specification](https://agentskills.io/specification) - a simple, open format for giving agents new capabilities and expertise. Skills are discovered automatically by compatible agents and activated based on context.

**Key Features:**
- Fast, deploy-only initialization that detects installed agents
- Skill-level setup scripts for on-demand dependencies
- Bundled tool packages inside skills (offline-friendly)
- Cross-platform support (Windows, Linux, macOS, containers)
- Future-friendly configuration for private NuGet feeds

## Quick Start (New Machine / Container)

### Prerequisites

- Windows: PowerShell 7+ recommended
- Linux/macOS: bash and coreutils
- Tool dependencies are installed on demand by skills (e.g., .NET 10 for SolarWinds logs, Node.js for WordPress)

### One-Command Setup

**Windows (PowerShell):**
```powershell
git clone https://github.com/jakenuts/agent-skills.git
cd agent-skills
.\init.ps1
```

**Linux/macOS:**
```bash
git clone https://github.com/jakenuts/agent-skills.git
cd agent-skills
chmod +x init.sh
./init.sh
```

`init` deploys skills only (no dependency installation). Tools are installed later when a skill is activated. If no agents are detected, install your agent CLI and rerun `init`.

**Docker Container:**
```dockerfile
FROM node:20-bookworm

# Install an agent CLI (example: Codex)
RUN npm install -g @openai/codex@latest

# Clone and deploy skills
RUN git clone https://github.com/jakenuts/agent-skills.git /opt/agent-skills
WORKDIR /opt/agent-skills
RUN chmod +x init.sh && ./init.sh

# Skills are deployed per-user. If you install the agent later, rerun init.
```

### What `init` Does

1. **Detects installed agents** - Looks for Claude Code and/or Codex CLI
2. **Deploys skills** - Copies skill definitions to the detected agent skill directories
3. **Optionally overwrites** - Use `--force` to replace existing skills

### Skill-Specific Configuration

Each skill documents its required environment variables, setup scripts, and validation steps in its `SKILL.md`.

## Supported Platforms

| Platform | Skills Location | Status |
|----------|-----------------|--------|
| Claude Code | `~/.claude/skills/` or `.claude/skills/` | Supported |
| Codex CLI | `~/.codex/skills/` | Experimental |
| Claude.ai | Upload via web interface | Supported |
| Claude API | Upload via API | Supported |

## Available Skills

### solarwinds-logs
Search and analyze production logs via SolarWinds Observability API.

**Use when:** Investigating errors, debugging issues, checking system health, or when user mentions logs, SolarWinds, or production errors.

**Bundled tool:** `logs` CLI (DealerVision.SolarWindsLogSearch)

**Required environment:** `SOLARWINDS_API_TOKEN`

### wordpress-content-manager
Manage WordPress blog content (list, search, create, update, delete posts) via the WordPress REST API.

**Use when:** Managing blog content for `blog.gbase.com` or similar WordPress sites configured via profiles.

**Dependencies:** Node.js 16+ and npm (installed on-demand by running the skill setup script)

**Required environment:** `WP_USERNAME`, `WP_APP_PASSWORD`

## Directory Structure

```
agent-skills/
├── docs/                        # Local reference docs
│   ├── agentskills-home.md      # Agent Skills overview (upstream copy)
│   └── developer-guidance.md
├── init.ps1                     # Windows initialization (single entrypoint)
├── init.sh                      # Linux/macOS initialization (single entrypoint)
├── config.json                  # Agent configuration (legacy tool config)
├── README.md                    # This file
├── tools/                       # Legacy bundled tool packages (optional)
│   └── solarwinds-logs/
│       └── *.nupkg             # .NET global tool package
├── scripts/                     # Utility scripts
│   ├── deploy.ps1              # Skills-only deployment (Windows)
│   ├── deploy.sh               # Skills-only deployment (Linux/macOS)
│   ├── validate.ps1            # Skill validation (Windows)
│   └── validate.sh             # Skill validation (Linux/macOS)
├── skills/                      # Skill definitions
│   ├── git-workflow/
│   ├── solarwinds-logs/
│   │   ├── SKILL.md            # Main skill file
│   │   ├── tools/              # Skill-local tool package(s)
│   │   ├── scripts/            # Skill setup scripts
│   │   └── references/
│   │       ├── REFERENCE.md    # Complete CLI reference
│   │       └── RECIPES.md      # Investigation patterns
│   └── wordpress-content-manager/
│       ├── SKILL.md
│       ├── profiles/
│       ├── references/
│       └── scripts/
└── .gitignore
```

## Init Script Options

### Windows (init.ps1)

```powershell
.\init.ps1          # Deploy to detected agents
.\init.ps1 -Force   # Overwrite existing skills
.\init.ps1 -DryRun  # Preview without changes
```

### Linux/macOS (init.sh)

```bash
./init.sh          # Deploy to detected agents
./init.sh -f       # Overwrite existing skills
./init.sh -d       # Preview without changes
```

## Developer Guidance

See `docs/developer-guidance.md` for the objective, init behavior, skill authoring checklist, and the self-setup dependency model used in this repo.

## Contributing

1. Create a new skill following the format above
2. Validate with `validate.ps1` or `validate.sh`
3. Test with your target agent
4. Submit a pull request

## Container Test Harness

If you need to validate the toolkit against containerized Claude Code or Codex
CLI installs, see `tests/containers/README.md` for a separate, optional test
harness that mounts this repo into a container and runs `init.sh`.

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- Local reference: `docs/agentskills-home.md` (from https://agentskills.io/home.md)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [OpenAI Codex Skills Documentation](https://github.com/openai/codex/blob/main/docs/skills.md)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)

## License

MIT License - See LICENSE file for details.
