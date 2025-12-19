# Agent Skills Toolkit

A unified collection of Agent Skills compatible with both **Claude Code** and **OpenAI Codex CLI**. Skills are modular capabilities that extend AI agents with specialized knowledge and workflows.

## Overview

This toolkit provides reusable skills that follow the [Agent Skills specification](https://agentskills.io/specification) - a simple, open format for giving agents new capabilities and expertise. Skills are discovered automatically by compatible agents and activated based on context.

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

**Prerequisites:**
- `logs` CLI tool installed
- `SOLARWINDS_API_TOKEN` environment variable

## Directory Structure

```
agent-skills/
├── README.md                    # This file
├── scripts/                     # Deployment and utility scripts
│   ├── deploy.ps1              # Windows deployment
│   ├── deploy.sh               # Linux/macOS deployment
│   └── validate.ps1            # Skill validation
├── skills/                      # Skill definitions
│   └── solarwinds-logs/
│       ├── SKILL.md            # Main skill file (required)
│       └── references/
│           ├── REFERENCE.md    # Complete CLI reference
│           └── RECIPES.md      # Investigation patterns
└── .gitignore
```

## Installation

### Quick Install (Recommended)

**Windows (PowerShell):**
```powershell
.\scripts\deploy.ps1 -Target claude
# or
.\scripts\deploy.ps1 -Target codex
# or both
.\scripts\deploy.ps1 -Target all
```

**Linux/macOS:**
```bash
./scripts/deploy.sh claude
# or
./scripts/deploy.sh codex
# or both
./scripts/deploy.sh all
```

### Manual Install

**Claude Code (Personal):**
```bash
# Windows
xcopy /E /I skills\* %USERPROFILE%\.claude\skills\

# Linux/macOS
cp -r skills/* ~/.claude/skills/
```

**Claude Code (Project):**
```bash
# Copy to project root
cp -r skills/* .claude/skills/
```

**Codex CLI:**
```bash
# Windows
xcopy /E /I skills\* %USERPROFILE%\.codex\skills\

# Linux/macOS
cp -r skills/* ~/.codex/skills/
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
   ```powershell
   .\scripts\validate.ps1 -Skill my-skill
   ```

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

## Contributing

1. Create a new skill following the format above
2. Validate with `validate.ps1`
3. Test with your target agent
4. Submit a pull request

## Resources

- [Agent Skills Specification](https://agentskills.io/specification)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [OpenAI Codex Skills Documentation](https://github.com/openai/codex/blob/main/docs/skills.md)
- [Anthropic Skills Repository](https://github.com/anthropics/skills)

## License

MIT License - See LICENSE file for details.
