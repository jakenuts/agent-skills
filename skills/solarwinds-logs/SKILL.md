---
name: solarwinds-logs
description: Search and analyze DealerVision production logs via SolarWinds Observability API. Use when investigating errors, debugging issues, checking system health, or when the user mentions logs, SolarWinds, production errors, or system monitoring. Requires the `logs` CLI tool to be installed.
---

# SolarWinds Log Search

Search DealerVision production logs through the SolarWinds Observability API using the `logs` CLI tool.

## Prerequisites

- The `logs` CLI must be installed (`dotnet tool install --global DealerVision.SolarWindsLogSearch`)
- `SOLARWINDS_API_TOKEN` environment variable must be set
- Default data center: `na-01`

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
