---
name: solarwinds-logs
description: Search and analyze DealerVision production logs via SolarWinds Observability API. Use when investigating errors, debugging issues, checking system health, or when the user mentions logs, SolarWinds, production errors, or system monitoring. Requires the `logs` CLI tool to be installed.
compatibility: Requires .NET SDK 10.0+, SOLARWINDS_API_TOKEN environment variable
allowed-tools: logs
metadata:
  requires-setup: true
  tool-name: solarwinds-logs
---

# SolarWinds Log Search

Search DealerVision production logs through the SolarWinds Observability API using the `logs` CLI tool.

## First-Time Setup (On Demand)
This skill requires the `logs` CLI tool, .NET 10, and a SolarWinds API token. Install only when the skill is activated.

### 1. Check if Already Installed

Linux/macOS:
```bash
logs --help 2>/dev/null || echo "Not installed - setup required"
echo "$SOLARWINDS_API_TOKEN"
```

Windows (PowerShell):
```powershell
logs --help 2>$null
Write-Host "SOLARWINDS_API_TOKEN=$env:SOLARWINDS_API_TOKEN"
```

### 2. Install Dependencies and Tool (One-Time Setup)

Run the setup script from the deployed skill folder:

Linux/macOS:
```bash
bash ~/.codex/skills/solarwinds-logs/scripts/setup.sh
```

Windows (PowerShell):
```powershell
pwsh ~/.codex/skills/solarwinds-logs/scripts/setup.ps1
```

If you are using Claude Code, replace `~/.codex/skills` with `~/.claude/skills`.

**What this does:**
- Installs .NET SDK 10 if missing (user-level)
- Installs the `logs` CLI tool from the skill-local package
- Verifies the installation
- Checks for required environment variables

**Note:** Installation only happens once; the tool becomes globally available.

### 3. Configure Environment Variable

The tool requires a SolarWinds API token for authentication.

Linux/macOS:
```bash
export SOLARWINDS_API_TOKEN="your-token-here"
```

Windows (PowerShell):
```powershell
$env:SOLARWINDS_API_TOKEN = "your-token-here"
```

**To obtain a token:**
1. Log in to SolarWinds Observability
2. Navigate to Settings -> API Tokens
3. Create a new token with 'Logs Read' permission

### 4. Verify Setup

Linux/macOS:
```bash
dotnet tool list --global | grep SolarWindsLogSearch
logs "test" --limit 1
```

Windows (PowerShell):
```powershell
dotnet tool list --global | Select-String SolarWindsLogSearch
logs "test" --limit 1
```

## Prerequisites

- **.NET SDK 10.0+** (required to install the tool)
- **SOLARWINDS_API_TOKEN** environment variable (required to use the tool)
- Default data center: `na-01`

## Alternative: Manual Installation

If you prefer to install manually without the setup script:

```bash
# Requires .NET SDK 10.0+
dotnet tool install --global DealerVision.SolarWindsLogSearch --version 2.4.0 --add-source ~/.codex/skills/solarwinds-logs/tools

# If using Claude Code, replace ~/.codex/skills with ~/.claude/skills
# Windows path: %USERPROFILE%\\.codex\\skills\\solarwinds-logs\\tools (or .claude for Claude Code)

# Verify
logs --help
```

## Quick Commands

```bash
# Search for errors
logs "error" --time-range 1h

# Find specific exceptions
logs "DbUpdateException" --severity ERROR --limit 10

# Filter by service
logs "timeout" --program webhook-api --time-range 4h

# Get full details for a specific log entry
logs --id 1901790063029837827 --with-data

# Export large result sets to file
logs "exception" --time-range 24h --output-file results.json
```

## Key Options

| Option | Description |
|--------|-------------|
| `--time-range` | `1h`, `4h`, `12h`, `24h`, `2d`, `7d`, `30d` |
| `--severity` | `INFO`, `WARN`, `ERROR`, `DEBUG` |
| `--program` | Filter by service name (e.g., `media-processing`) |
| `--hostname` | Filter by host |
| `--limit` | Max results (default 1000, max 50000) |
| `--with-data` | Include structured JSON payload |
| `--no-data` | Exclude payload (faster, smaller response) |
| `--output-file` | Save full results to file |

## Workflow Strategy

1. **Start broad** - Run initial search without many filters
2. **Narrow progressively** - Add severity, time-range, or program filters based on results
3. **Retrieve details** - Use `--id` with `--with-data` for full log entry inspection
4. **Export large datasets** - Use `--output-file` for comprehensive analysis

## Output Format

Returns JSON with:
- `success`: boolean status
- `query`: search parameters used
- `summary`: statistics including severity breakdown, truncation info
- `results`: array of log entries with timestamps, source, severity, message
- `pagination`: info for getting more results

## Advanced Usage

For detailed documentation on query syntax, MCP server modes, and advanced patterns, see [references/REFERENCE.md](references/REFERENCE.md).

For common investigation patterns and recipes, see [references/RECIPES.md](references/RECIPES.md).




