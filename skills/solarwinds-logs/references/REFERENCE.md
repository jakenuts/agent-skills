# SolarWinds Logs - Complete Reference

## Query Syntax

### Basic Search
Every positional argument is appended to the query text with implicit AND:
```bash
logs timeout database    # Same as: logs "timeout database"
```

### Boolean Operators
Use quotes for phrases or punctuation:
```bash
logs "\"Photo #1\" car_id Completed"
```

SolarWinds query operators (case-sensitive):
- `AND`, `OR`, `NOT`
- Parentheses for grouping
- Field filters: `program:webhook-api`, `message:"marked 'Completed'"`

### Filter Injection
Structured flags automatically inject query tokens:
- `--hostname foo` becomes `hostname:"foo"`
- `--program bar` becomes `program:"bar"`
- `--severity WARN` becomes `severity:WARN`

## CLI Options - Complete Reference

### Search Parameters
| Option | Alias | Description | Default |
|--------|-------|-------------|---------|
| `query` | - | Search query (positional argument) | - |
| `--limit` | `-l` | Maximum results (1-50000) | 1000 |
| `--time-range` | `-t` | Time window: 1h, 4h, 12h, 24h, 2d, 7d, 30d (⚠️ see warning below) | all logs |
| `--start-time` | `--from` | Start time (ISO 8601) (⚠️ see warning below) | - |
| `--end-time` | `--to` | End time (ISO 8601) (⚠️ see warning below) | - |
| `--continuation-token` | `-c` | Resume from previous response | - |

> **⚠️ Time Argument Warning:** The SolarWinds/Papertrail API is finicky with time ranges and often **skips recent/current entries** when time arguments are used. The `logs` tool is designed to start from the most recent entries and page backward automatically. **Prefer simple searches without time arguments** (e.g., `logs 'error'`) and filter results afterward. Only use time arguments when you explicitly need to exclude current results or investigate a specific historical window. See SKILL.md for detailed guidance.

### Filters
| Option | Description |
|--------|-------------|
| `--severity` | INFO, WARN, ERROR, DEBUG |
| `--hostname` | Filter by hostname |
| `--program` | Filter by program/service |

### Data Control
| Option | Description |
|--------|-------------|
| `--with-data` | Include structured JSON payload |
| `--no-data` | Exclude payload (default for search) |
| `--with-message` | Include message text (default) |
| `--no-message` | Exclude message text |

### ID Retrieval
| Option | Description |
|--------|-------------|
| `--id` | Retrieve single entry by ID (implies --with-data) |
| `--ids` | Comma-separated IDs (max 50) |

### Output Control
| Option | Alias | Description |
|--------|-------|-------------|
| `--pretty` | `-p` | Pretty-print JSON |
| `--output-file` | `-o` | Write results to file |
| `--output-dir` | - | Directory for large results |
| `--export-format` | - | json (default) or ndjson |
| `--no-truncation` | `--no-limits` | Disable safety caps |
| `--max-response-size` | - | Max response size in KB (default 50) |

### Authentication
| Option | Description |
|--------|-------------|
| `--api-token` | SolarWinds API token (or use env var) |
| `--data-center` / `--dc` | Data center: na-01 (default), eu-01, etc. |

### Debugging
| Option | Alias | Description |
|--------|-------|-------------|
| `--debug` | `-d` | Enable diagnostics |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SOLARWINDS_API_TOKEN` | Bearer credentials (required) |
| `SOLARWINDS_OBSERVABILITY_TOKEN` | Alias for above |
| `SOLARWINDS_TOKEN` | Alias for above |
| `SOLARWINDS_LOGS_MAX_RESPONSE_SIZE` | Override 50KB default |
| `SOLARWINDS_LOGS_OUTPUT_DIR` | Directory for large responses |

## MCP Server Mode

### Stdio Transport (Local Agents)
```bash
logs serve --transport stdio --api-token $SOLARWINDS_API_TOKEN --data-center na-01
```

### HTTP/SSE Transport (Remote Agents)
```bash
logs serve --transport http --host 0.0.0.0 --port 8080 --api-token $TOKEN
```

### Security Options
| Option | Description |
|--------|-------------|
| `--auth-token` | Require Bearer token on requests |
| `--allow-origin` | Enforce Origin headers |
| `--allow-client-token` | Allow clients to provide their own credentials |
| `--disable-sse` | Disable streaming responses |
| `--log-file` | Path for diagnostic logging |

### Client Configuration

**Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "solarwinds-logs": {
      "command": "logs",
      "args": ["serve", "--transport", "stdio", "--data-center", "na-01"]
    }
  }
}
```

**Claude Code** (VS Code settings.json):
```jsonc
"claudeCode.mcpServers": [
  {
    "name": "solarwinds-logs",
    "command": "logs",
    "args": ["serve", "--transport", "stdio", "--data-center", "na-01"],
    "env": { "SOLARWINDS_API_TOKEN": "${env:SOLARWINDS_API_TOKEN}" }
  }
]
```

**Codex CLI** (`~/.codex/mcp.json`):
```json
{
  "servers": [
    {
      "name": "solarwinds-logs",
      "command": "logs",
      "args": ["serve", "--transport", "stdio", "--data-center", "na-01"],
      "env": { "SOLARWINDS_API_TOKEN": "${env:SOLARWINDS_API_TOKEN}" }
    }
  ]
}
```

## MCP Tools

When running as MCP server, two tools are exposed:

### solarwinds.logs.search
Search logs with optional filters and pagination.

> **⚠️ Important:** Prefer simple searches without `timeRange`, `startTime`, or `endTime` parameters. The API often skips recent entries when time arguments are used. Run simple queries like `query: "error"` and filter results afterward. Only use time parameters when explicitly excluding current results or investigating a specific historical window.

Parameters:
- `query`: Search query
- `limit`: Max results
- `timeRange`: Time window (1h, 24h, 7d, etc.) — ⚠️ avoid unless excluding recent results
- `startTime`, `endTime`: Specific time window — ⚠️ avoid unless excluding recent results
- `continuationToken`: For pagination
- `includeData`: Include structured payload (default: false)
- `includeMessage`: Include message text (default: true)
- `noTruncation`: Disable response truncation
- `severity`, `hostname`, `program`: Filters
- `id`, `ids`: Retrieve specific entries

### solarwinds.logs.count
Count matching entries and return aggregations.

Parameters:
- `query`: Search query
- `limit`: Max events to inspect (default: 5000)
- `timeRange`: Time window
- `startTime`, `endTime`: Specific time window
- `severity`, `hostname`, `program`: Filters
- `groupBy`: Fields to group by (program, system, severity, day)
- `top`: Max buckets per group (1-25, default: 10)

## Response Schema

```json
{
  "success": true,
  "query": {
    "search_term": "error",
    "time_range": { "from": "...", "to": "...", "description": "..." },
    "limit": 50,
    "filters_applied": ["API: SolarWinds Observability (na-01)"]
  },
  "summary": {
    "total_found": 12,
    "returned": 8,
    "earliest_timestamp": "2025-10-01T01:15:22Z",
    "latest_timestamp": "2025-10-01T02:45:00Z",
    "sources": { "media-events": 5, "webhook-api": 3 },
    "severity_breakdown": { "ERROR": 6, "WARN": 2 },
    "truncated": false,
    "pages_searched": 1,
    "api_calls_made": 1
  },
  "results": [
    {
      "timestamp": "2025-10-01T01:15:22Z",
      "source": "",
      "source_name": "fieldservice-web",
      "hostname": "fieldservice-web",
      "severity": "ERROR",
      "message": "PublishedCarPhoto failed",
      "program": "fieldservice-web",
      "data": null,
      "has_data": true,
      "id": "1901790063029837827"
    }
  ],
  "error": null,
  "warning": null,
  "pagination": {
    "has_more": false,
    "next_token": null
  }
}
```

## Performance Notes

- Default lookback without time filters: 24 hours
- Searches without results complete in ~30 seconds
- Large requests use automatic backward time chunking
- Allow ~90 seconds per request for large result sets
- Use `--no-data` for faster, smaller responses
- Progress is printed to stderr during chunking
