# SolarWinds Logs - Investigation Recipes

## Common Investigation Patterns

### 1. Error Investigation

**Initial broad search:**
```bash
logs "error" --severity ERROR --time-range 1h
```

**Narrow to specific service:**
```bash
logs "error" --severity ERROR --program webhook-api --time-range 1h
```

**Get full context for specific error:**
```bash
logs --id 1901790063029837827 --with-data --pretty
```

### 2. Exception Tracing

**Find all exceptions:**
```bash
logs "Exception" --severity ERROR --time-range 4h --limit 50
```

**Track specific exception type:**
```bash
logs "DbUpdateException" --severity ERROR --time-range 24h
```

**Database-related issues:**
```bash
logs "deadlock OR timeout OR \"connection pool\"" --severity ERROR --time-range 2h
```

### 3. Service Health Check

**Recent activity for a service:**
```bash
logs --program media-processing --time-range 1h --limit 100
```

**Error rate check:**
```bash
logs --program media-processing --severity ERROR --time-range 24h
```

**Warnings that might indicate issues:**
```bash
logs --program media-processing --severity WARN --time-range 4h
```

### 4. Workflow Debugging

**Track specific workflow execution:**
```bash
logs "workflow_id:abc123" --with-data --time-range 24h
```

**Find workflow failures:**
```bash
logs "workflow failed OR workflow error" --severity ERROR --time-range 4h
```

**Track message processing:**
```bash
logs "message_id:xyz789" --with-data
```

### 5. User/Entity Investigation

**Find logs for specific car:**
```bash
logs "car_id:68619" --time-range 7d --with-data
```

**Track dealer activity:**
```bash
logs "dealer_id:12345" --time-range 24h
```

**Find assignment-related logs:**
```bash
logs "assignment_id:9510" --with-data
```

### 6. Performance Investigation

**Find slow operations:**
```bash
logs "timeout OR slow OR latency" --time-range 2h
```

**Queue/messaging issues:**
```bash
logs "SQS OR queue OR visibility" --program webhook-api --time-range 4h
```

**Memory/resource issues:**
```bash
logs "OutOfMemory OR memory OR heap" --severity ERROR --time-range 24h
```

### 7. Integration Issues

**External API failures:**
```bash
logs "API error OR 502 OR 503 OR gateway" --severity ERROR --time-range 2h
```

**Authentication failures:**
```bash
logs "unauthorized OR authentication OR 401" --severity ERROR --time-range 4h
```

### 8. Deployment Verification

**Check recent deployment health:**
```bash
logs "startup OR initialized OR ready" --time-range 1h
```

**Find deployment-time errors:**
```bash
logs --severity ERROR --time-range 30m
```

## Export Patterns

### Export for analysis tools:
```bash
logs "error" --time-range 24h --no-truncation --output-file errors.json
```

### Export as newline-delimited JSON:
```bash
logs "exception" --time-range 7d --export-format ndjson --output-file exceptions.ndjson
```

### Export with full structured data:
```bash
logs "workflow" --with-data --no-truncation --output-file workflow-debug.json
```

## Pagination for Large Result Sets

**Initial query:**
```bash
logs "error" --time-range 7d --limit 1000
```

**Continue from previous results:**
```bash
logs "error" --continuation-token "<token_from_previous_response>"
```

## Multi-Step Investigation Flow

1. **Identify the issue:**
   ```bash
   logs "error" --severity ERROR --time-range 1h
   ```

2. **Narrow down the service:**
   ```bash
   logs "error" --severity ERROR --program identified-service --time-range 1h
   ```

3. **Get timeline context:**
   ```bash
   logs --program identified-service --time-range 2h --limit 200
   ```

4. **Deep dive on specific entry:**
   ```bash
   logs --id specific-log-id --with-data --pretty
   ```

5. **Export for documentation:**
   ```bash
   logs --ids id1,id2,id3 --with-data --output-file investigation.json
   ```

## Tips

- **Start without filters** - Let the summary show you what's in the logs
- **Use severity breakdown** - The response includes severity counts to guide filtering
- **Check `has_data`** - Entries with `has_data: true` have structured payload available
- **Use `--pretty` for reading** - Makes JSON output human-readable
- **Export large results** - Use `--output-file` to avoid context window bloat
- **Time windows matter** - Larger ranges are significantly slower; start small
