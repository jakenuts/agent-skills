# Agent Skills Toolkit

A unified collection of Agent Skills compatible with both **Claude Code** and **OpenAI Codex CLI**. Skills are modular capabilities that extend AI agents with specialized knowledge and workflows.

## Overview

This toolkit provides reusable skills that follow the [Agent Skills specification](https://agentskills.io/specification) - a simple, open format for giving agents new capabilities and expertise. Skills are discovered automatically by compatible agents and activated based on context.

**Key Features:**
- Single `init` script for complete environment setup
- Bundled CLI tools (no external package feeds required)
- Cross-platform support (Windows, Linux, macOS, containers)
- Future-friendly configuration for private NuGet feeds

## Quick Start (New Machine / Container)

### Prerequisites

- [.NET SDK 8.0+](https://dotnet.microsoft.com/download) installed
- `jq` installed (Linux/macOS only, for JSON parsing)

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

**Docker Container:**
```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:9.0

# Install jq for JSON parsing
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

# Clone and initialize
RUN git clone https://github.com/jakenuts/agent-skills.git /opt/agent-skills
WORKDIR /opt/agent-skills
RUN chmod +x init.sh && ./init.sh --skip-skills

# Skills are deployed per-user, so deploy at runtime or for specific user
```

### What `init` Does

1. **Checks prerequisites** - Verifies .NET SDK is installed
2. **Installs CLI tools** - Installs bundled tools (e.g., `logs`) as global .NET tools
3. **Deploys skills** - Copies skill definitions to agent skill directories
4. **Validates** - Confirms tools respond and skills are in place

### Post-Init Configuration

Set required environment variables:
```bash
# Windows (PowerShell)
$env:SOLARWINDS_API_TOKEN = "your-token-here"
# Or permanently: [Environment]::SetEnvironmentVariable("SOLARWINDS_API_TOKEN", "your-token", "User")

# Linux/macOS
export SOLARWINDS_API_TOKEN="your-token-here"
# Add to ~/.bashrc or ~/.zshrc for persistence
```

Restart your terminal and test:
```bash
logs --help
```

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

## Directory Structure

```
agent-skills/
├── init.ps1                     # Windows initialization (single entrypoint)
├── init.sh                      # Linux/macOS initialization (single entrypoint)
├── config.json                  # Tool sources and agent configuration
├── README.md                    # This file
├── tools/                       # Bundled CLI tool packages
│   └── solarwinds-logs/
│       └── *.nupkg             # .NET global tool package
├── scripts/                     # Utility scripts
│   ├── deploy.ps1              # Skills-only deployment (Windows)
│   ├── deploy.sh               # Skills-only deployment (Linux/macOS)
│   ├── validate.ps1            # Skill validation (Windows)
│   └── validate.sh             # Skill validation (Linux/macOS)
├── skills/                      # Skill definitions
│   └── solarwinds-logs/
│       ├── SKILL.md            # Main skill file
│       └── references/
│           ├── REFERENCE.md    # Complete CLI reference
│           └── RECIPES.md      # Investigation patterns
└── .gitignore
```

## Init Script Options

### Windows (init.ps1)

```powershell
.\init.ps1                           # Full setup, all agents
.\init.ps1 -Target claude            # Claude Code only
.\init.ps1 -Target codex             # Codex CLI only
.\init.ps1 -SkipTools                # Deploy skills only
.\init.ps1 -SkipSkills               # Install tools only
.\init.ps1 -Force                    # Overwrite existing
.\init.ps1 -DryRun                   # Preview without changes
.\init.ps1 -ToolSource nuget-private # Use private NuGet feed
```

### Linux/macOS (init.sh)

```bash
./init.sh                            # Full setup, all agents
./init.sh -t claude                  # Claude Code only
./init.sh -t codex                   # Codex CLI only
./init.sh --skip-tools               # Deploy skills only
./init.sh --skip-skills              # Install tools only
./init.sh -f                         # Overwrite existing
./init.sh -d                         # Preview without changes
./init.sh -s nuget-private           # Use private NuGet feed
```

## Tool Distribution

### Current: Bundled Local Packages

Tools are distributed as NuGet packages bundled in the `tools/` directory. This approach:
- Works offline / in air-gapped environments
- Requires no external authentication
- Makes versioning explicit in the repo

### Future: Private NuGet Feed

The `config.json` supports multiple tool sources. To switch to a private feed:

1. Edit `config.json`:
   ```json
   "tools": {
     "solarwinds-logs": {
       "source": "nuget-private",
       "sources": {
         "nuget-private": {
           "type": "nuget",
           "url": "https://pkgs.dev.azure.com/YOUR_ORG/_packaging/YOUR_FEED/nuget/v3/index.json"
         }
       }
     }
   }
   ```

2. Configure NuGet authentication:
   ```bash
   dotnet nuget add source "https://..." --name "private" --username "user" --password "PAT"
   ```

3. Run init with the new source:
   ```bash
   ./init.sh -s nuget-private
   ```

## Creating New Skills

1. Create a new directory under `skills/`:
   ```bash
   mkdir -p skills/my-skill/references
   ```

2. Create `SKILL.md` with required frontmatter:
   ```yaml
   ---
   name: my-skill
   description: Clear description of what this skill does and when to use it.
   ---

   # My Skill Name

   ## Instructions
   [Your instructions here]
   ```

3. Add optional reference files in `references/` for detailed documentation

4. Validate the skill:
   ```bash
   # Windows
   .\scripts\validate.ps1 -Skill my-skill

   # Linux/macOS
   ./scripts/validate.sh my-skill
   ```

## Adding New Tools

1. Build or obtain the `.nupkg` file for the tool

2. Create a directory under `tools/`:
   ```bash
   mkdir tools/my-tool
   cp MyTool.1.0.0.nupkg tools/my-tool/
   ```

3. Add configuration to `config.json`:
   ```json
   "tools": {
     "my-tool": {
       "packageId": "MyTool.Package.Id",
       "version": "1.0.0",
       "command": "mytool",
       "source": "local",
       "sources": {
         "local": {
           "type": "local",
           "path": "tools/my-tool"
         }
       }
     }
   }
   ```

4. Run `init` to install

## Skill Format

Skills use YAML frontmatter in a Markdown file:

### Required Fields
- `name`: 1-64 characters, lowercase alphanumeric and hyphens only
- `description`: 1-1024 characters describing what and when to use the skill

### Optional Fields
- `allowed-tools`: Space-delimited list of permitted tools
- `license`: Licensing terms
- `compatibility`: Environment requirements
- `metadata`: Additional key-value pairs

### Progressive Disclosure

Skills follow a three-tier context model:
1. **Metadata** (~100 tokens): Name and description loaded at startup
2. **Instructions** (<5000 tokens): Full SKILL.md when activated
3. **Resources** (as needed): Reference files loaded on-demand

## Best Practices

1. **Keep skills focused**: One skill = one capability
2. **Write clear descriptions**: Include specific triggers and file types
3. **Use progressive disclosure**: Put detailed docs in reference files
4. **Test across platforms**: Verify on both Claude Code and Codex CLI
5. **Bundle dependencies**: Include tool packages for offline use

## Contributing

1. Create a new skill following the format above
2. Validate with `validate.ps1` or `validate.sh`
3. Test with your target agent
4. Submit a pull request

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [OpenAI Codex Skills Documentation](https://github.com/openai/codex/blob/main/docs/skills.md)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)

## License

MIT License - See LICENSE file for details.
