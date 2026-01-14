# Agent Skills Toolkit

A unified collection of Agent Skills and Expert Agent definitions compatible with both **Claude Code** and **OpenAI Codex CLI**. This toolkit provides modular capabilities that extend AI agents with specialized knowledge, workflows, and expert sub-agents.

## Overview

This toolkit provides:
- **Skills**: Reusable capabilities following the [Agent Skills specification](https://agentskills.io/specification) - activated based on context
- **Expert Agents**: Specialized sub-agent definitions that can be invoked via the Task tool for complex, multi-step operations

**Key Features:**
- Fast, deploy-only initialization that detects installed agents
- Skill-level setup scripts for on-demand dependencies
- Bundled tool packages inside skills (offline-friendly)
- Hierarchical expert agent organization (core, orchestrators, specialized, universal)
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
3. **Deploys expert agents** - Copies agent definition files to the agents directory (preserving hierarchical structure)
4. **Optionally overwrites** - Use `--force` to replace existing skills and agents

### Skill-Specific Configuration

Each skill documents its required environment variables, setup scripts, and validation steps in its `SKILL.md`.

### Expert Agent Organization

Expert agents are organized hierarchically:
- **core**: General-purpose agents (code-archaeologist, code-reviewer, performance-optimizer)
- **orchestrators**: High-level coordinators (dotnet-solution-architect, modern-frontend-architect, tech-lead-orchestrator)
- **specialized**: Technology-specific experts (dotnet, react, vue, database, mapping, etc.)
- **universal**: Framework-agnostic helpers (api-architect, backend-developer, frontend-developer)

## Supported Platforms

| Platform | Skills Location | Agents Location | Status |
|----------|-----------------|-----------------|--------|
| Claude Code | `~/.claude/skills/` | `~/.claude/agents/` | Supported |
| Codex CLI | `~/.codex/skills/` | `~/.codex/agents/` | Experimental |
| Claude.ai | Upload via web interface | N/A | Skills only |
| Claude API | Upload via API | N/A | Skills only |

## Available Skills

### solarwinds-logs
Search and analyze production logs via SolarWinds Observability API.

**Use when:** Investigating errors, debugging issues, checking system health, or when user mentions logs, SolarWinds, or production errors.

**Bundled tool:** `logs` CLI (DealerVision.SolarWindsLogSearch)

**Required environment:** `SOLARWINDS_API_TOKEN`

### wordpress-content-manager
Manage WordPress blog content (list, search, create, update, delete posts) via the WordPress REST API.

**Use when:** Managing WordPress blog content.

**Dependencies:** Node.js 16+ and npm (installed on-demand by running the skill setup script)

**Required environment:** `WP_SITE_URL`, `WP_USERNAME`, `WP_APP_PASSWORD`

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
│       ├── scripts/
│       └── references/
├── agents/                      # Expert agent definitions (payload)
│   ├── core/                    # General-purpose agents
│   │   ├── code-archaeologist.md
│   │   ├── code-reviewer.md
│   │   └── performance-optimizer.md
│   ├── orchestrators/           # High-level coordinators
│   │   ├── dotnet-solution-architect.md
│   │   ├── modern-frontend-architect.md
│   │   └── tech-lead-orchestrator.md
│   ├── specialized/             # Technology-specific experts
│   │   ├── dotnet/
│   │   ├── react/
│   │   ├── vue/
│   │   ├── database/
│   │   └── mapping/
│   └── universal/               # Framework-agnostic helpers
│       ├── api-architect.md
│       ├── backend-developer.md
│       └── frontend-developer.md
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

## Context Window Management

**Expert agents use progressive disclosure** to minimize context usage:
- Agent definitions contain concise YAML frontmatter with name, description, and examples
- Full agent prompts are only loaded when explicitly invoked via the Task tool
- Hierarchical organization helps Claude Code select the right specialist without loading all definitions
- Similar to skills, this "lazy loading" approach prevents context window overload

**Best Practices:**
- Agent definitions are indexed by name and description only
- When you invoke an agent via `Task(subagent_type="agent-name")`, only that agent's full definition is loaded
- The hierarchical structure (core/orchestrators/specialized/universal) provides semantic grouping without impacting context

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Claude Code Sub-Agents Best Practices](https://www.pubnub.com/blog/best-practices-for-claude-code-sub-agents/)
- [Rosmur's Claude Code Best Practices](https://rosmur.github.io/claudecode-best-practices/)
- [OpenAI Codex Skills Documentation](https://github.com/openai/codex/blob/main/docs/skills.md)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)

## License

MIT License - See LICENSE file for details.
