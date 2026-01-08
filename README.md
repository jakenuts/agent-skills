# Agent Skills Toolkit

A unified collection of Agent Skills compatible with both **Claude Code** and **OpenAI Codex CLI**. Skills are modular capabilities that extend AI agents with specialized knowledge and workflows.

## Overview

This toolkit provides reusable skills that follow the [Agent Skills specification](https://agentskills.io/specification) - a simple, open format for giving agents new capabilities and expertise. Skills are discovered automatically by compatible agents and activated based on context.

**Key Features:**
- Fast, deploy-only initialization that detects installed agents
- Skill-level setup scripts for on-demand dependencies
- Bundled tool packages inside skills (offline-friendly)
- Cross-platform support (Windows, Linux, macOS, containers)

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

**Use when:** Managing WordPress sites configured via profiles.

**Dependencies:** Node.js 16+ and npm (installed on-demand by running the skill setup script)

**Required environment:** `WP_USERNAME`, `WP_APP_PASSWORD`

### git-workflow
Automated git workflow helpers for common development tasks.

**Use when:** Creating feature branches, cleaning up merged branches, or interactive rebasing.

**Dependencies:** None - uses native git commands.

## Directory Structure

```
agent-skills/
├── init.ps1                     # Windows initialization
├── init.sh                      # Linux/macOS initialization
├── README.md                    # This file
├── LICENSE
├── scripts/                     # Deployment scripts
│   ├── deploy.ps1
│   └── deploy.sh
├── skills/                      # Skill definitions (payload)
│   ├── git-workflow/
│   │   ├── SKILL.md
│   │   └── scripts/
│   ├── solarwinds-logs/
│   │   ├── SKILL.md
│   │   ├── tools/               # Bundled .nupkg
│   │   ├── scripts/             # Setup scripts
│   │   └── references/
│   └── wordpress-content-manager/
│       ├── SKILL.md
│       ├── profiles/
│       ├── scripts/
│       └── references/
└── .dev/                        # Development infrastructure (not deployed)
    ├── tests/                   # Container test harness
    ├── docs/                    # Internal documentation
    └── scripts/                 # Dev utilities (validate, etc.)
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

## Development

### Validating Skills

```bash
bash .dev/scripts/validate.sh [skill-name]
```

### Container Testing

See `.dev/tests/containers/README.md` for the container test harness that validates skill deployment in containerized Claude Code and Codex CLI environments.

## Contributing

1. Create a new skill following the format above
2. Validate with `.dev/scripts/validate.sh`
3. Test with your target agent
4. Submit a pull request

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [OpenAI Codex Skills Documentation](https://github.com/openai/codex/blob/main/docs/skills.md)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)

## License

MIT License - See LICENSE file for details.
