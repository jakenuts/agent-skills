# Cloudflare API v4 Reference

**Skill by After Dark Systems, LLC**

## Base URL

```
https://api.cloudflare.com/client/v4
```

## Authentication

### API Token (Recommended)
```bash
Authorization: Bearer <API_TOKEN>
```

### Global API Key (Legacy)
```bash
X-Auth-Email: <EMAIL>
X-Auth-Key: <GLOBAL_API_KEY>
```

## Response Format

All responses follow this structure:

```json
{
  "success": true,
  "errors": [],
  "messages": [],
  "result": { ... },
  "result_info": {
    "page": 1,
    "per_page": 20,
    "total_pages": 1,
    "count": 1,
    "total_count": 1
  }
}
```

## Rate Limiting

- 1200 requests per 5 minutes per user
- Some endpoints have stricter limits
- Rate limit headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`

---

## Zones API

### List Zones
```
GET /zones
```

Query Parameters:
- `name` - Filter by domain name
- `status` - Filter by status (active, pending, initializing, moved, deleted, deactivated)
- `page` - Page number
- `per_page` - Results per page (max 50)
- `order` - Order by (name, status, email)
- `direction` - Sort direction (asc, desc)

### Get Zone Details
```
GET /zones/{zone_id}
```

### Create Zone
```
POST /zones
```

Body:
```json
{
  "name": "example.com",
  "account": {
    "id": "account_id"
  },
  "type": "full"
}
```

### Delete Zone
```
DELETE /zones/{zone_id}
```

### Zone Activation Check
```
PUT /zones/{zone_id}/activation_check
```

---

## DNS Records API

### List DNS Records
```
GET /zones/{zone_id}/dns_records
```

Query Parameters:
- `type` - Record type (A, AAAA, CNAME, MX, TXT, NS, etc.)
- `name` - Record name
- `content` - Record content
- `proxied` - Proxied status (true/false)
- `page`, `per_page` - Pagination

### Get DNS Record
```
GET /zones/{zone_id}/dns_records/{record_id}
```

### Create DNS Record
```
POST /zones/{zone_id}/dns_records
```

Body (A Record):
```json
{
  "type": "A",
  "name": "subdomain.example.com",
  "content": "192.0.2.1",
  "ttl": 3600,
  "proxied": true
}
```

Body (MX Record):
```json
{
  "type": "MX",
  "name": "example.com",
  "content": "mail.example.com",
  "ttl": 3600,
  "priority": 10
}
```

Body (TXT Record):
```json
{
  "type": "TXT",
  "name": "example.com",
  "content": "v=spf1 include:_spf.google.com ~all",
  "ttl": 3600
}
```

### Update DNS Record
```
PATCH /zones/{zone_id}/dns_records/{record_id}
```

### Delete DNS Record
```
DELETE /zones/{zone_id}/dns_records/{record_id}
```

### Import DNS Records
```
POST /zones/{zone_id}/dns_records/import
```

Content-Type: multipart/form-data
- `file` - BIND zone file

### Export DNS Records
```
GET /zones/{zone_id}/dns_records/export
```

---

## SSL/TLS API

### Get SSL Setting
```
GET /zones/{zone_id}/settings/ssl
```

### Update SSL Setting
```
PATCH /zones/{zone_id}/settings/ssl
```

Body:
```json
{
  "value": "strict"
}
```

Values: `off`, `flexible`, `full`, `strict`

### Get SSL Verification
```
GET /zones/{zone_id}/ssl/verification
```

### Get Certificate Packs
```
GET /zones/{zone_id}/ssl/certificate_packs
```

### Order Advanced Certificate
```
POST /zones/{zone_id}/ssl/certificate_packs/order
```

Body:
```json
{
  "type": "advanced",
  "hosts": ["example.com", "*.example.com"],
  "validation_method": "txt",
  "validity_days": 365,
  "certificate_authority": "digicert"
}
```

---

## Cache API

### Purge All Files
```
POST /zones/{zone_id}/purge_cache
```

Body:
```json
{
  "purge_everything": true
}
```

### Purge by URL
```
POST /zones/{zone_id}/purge_cache
```

Body:
```json
{
  "files": [
    "https://example.com/styles.css",
    "https://example.com/scripts.js"
  ]
}
```

### Purge by Cache Tags
```
POST /zones/{zone_id}/purge_cache
```

Body:
```json
{
  "tags": ["tag1", "tag2"]
}
```

### Purge by Prefix
```
POST /zones/{zone_id}/purge_cache
```

Body:
```json
{
  "prefixes": ["example.com/static/"]
}
```

### Purge by Host
```
POST /zones/{zone_id}/purge_cache
```

Body:
```json
{
  "hosts": ["www.example.com", "images.example.com"]
}
```

---

## Firewall Rules API

### List Firewall Rules
```
GET /zones/{zone_id}/firewall/rules
```

### Create Firewall Rule
```
POST /zones/{zone_id}/firewall/rules
```

Body:
```json
[
  {
    "action": "block",
    "filter": {
      "expression": "(ip.src eq 192.0.2.1)"
    },
    "description": "Block bad actor"
  }
]
```

Actions: `block`, `challenge`, `js_challenge`, `managed_challenge`, `allow`, `log`, `bypass`

### Update Firewall Rule
```
PUT /zones/{zone_id}/firewall/rules/{rule_id}
```

### Delete Firewall Rule
```
DELETE /zones/{zone_id}/firewall/rules/{rule_id}
```

---

## IP Access Rules API

### List Access Rules
```
GET /zones/{zone_id}/firewall/access_rules/rules
```

### Create Access Rule
```
POST /zones/{zone_id}/firewall/access_rules/rules
```

Body:
```json
{
  "mode": "block",
  "configuration": {
    "target": "ip",
    "value": "192.0.2.1"
  },
  "notes": "Blocking suspicious IP"
}
```

Modes: `block`, `challenge`, `whitelist`, `js_challenge`, `managed_challenge`
Targets: `ip`, `ip_range`, `asn`, `country`

### Delete Access Rule
```
DELETE /zones/{zone_id}/firewall/access_rules/rules/{rule_id}
```

---

## WAF (Web Application Firewall) API

### List WAF Packages
```
GET /zones/{zone_id}/firewall/waf/packages
```

### Get WAF Package
```
GET /zones/{zone_id}/firewall/waf/packages/{package_id}
```

### List WAF Rule Groups
```
GET /zones/{zone_id}/firewall/waf/packages/{package_id}/groups
```

### Update WAF Rule Group
```
PATCH /zones/{zone_id}/firewall/waf/packages/{package_id}/groups/{group_id}
```

Body:
```json
{
  "mode": "on"
}
```

---

## Rate Limiting API

### List Rate Limits
```
GET /zones/{zone_id}/rate_limits
```

### Create Rate Limit
```
POST /zones/{zone_id}/rate_limits
```

Body:
```json
{
  "match": {
    "request": {
      "url_pattern": "*",
      "methods": ["GET", "POST"]
    }
  },
  "threshold": 100,
  "period": 60,
  "action": {
    "mode": "challenge",
    "timeout": 3600
  },
  "disabled": false,
  "description": "Rate limit API"
}
```

### Delete Rate Limit
```
DELETE /zones/{zone_id}/rate_limits/{rate_limit_id}
```

---

## Page Rules API

### List Page Rules
```
GET /zones/{zone_id}/pagerules
```

### Create Page Rule
```
POST /zones/{zone_id}/pagerules
```

Body:
```json
{
  "targets": [
    {
      "target": "url",
      "constraint": {
        "operator": "matches",
        "value": "*example.com/images/*"
      }
    }
  ],
  "actions": [
    {
      "id": "cache_level",
      "value": "cache_everything"
    },
    {
      "id": "edge_cache_ttl",
      "value": 86400
    }
  ],
  "status": "active",
  "priority": 1
}
```

### Update Page Rule
```
PATCH /zones/{zone_id}/pagerules/{pagerule_id}
```

### Delete Page Rule
```
DELETE /zones/{zone_id}/pagerules/{pagerule_id}
```

---

## Workers API

### List Workers
```
GET /accounts/{account_id}/workers/scripts
```

### Get Worker Script
```
GET /accounts/{account_id}/workers/scripts/{script_name}
```

### Upload Worker Script
```
PUT /accounts/{account_id}/workers/scripts/{script_name}
```

Content-Type: application/javascript

Body: JavaScript code

### Delete Worker Script
```
DELETE /accounts/{account_id}/workers/scripts/{script_name}
```

### List Worker Routes
```
GET /zones/{zone_id}/workers/routes
```

### Create Worker Route
```
POST /zones/{zone_id}/workers/routes
```

Body:
```json
{
  "pattern": "example.com/api/*",
  "script": "my-worker"
}
```

### Delete Worker Route
```
DELETE /zones/{zone_id}/workers/routes/{route_id}
```

---

## Pages API

### List Pages Projects
```
GET /accounts/{account_id}/pages/projects
```

### Get Pages Project
```
GET /accounts/{account_id}/pages/projects/{project_name}
```

### Create Pages Project
```
POST /accounts/{account_id}/pages/projects
```

Body:
```json
{
  "name": "my-project",
  "production_branch": "main"
}
```

### Delete Pages Project
```
DELETE /accounts/{account_id}/pages/projects/{project_name}
```

### List Deployments
```
GET /accounts/{account_id}/pages/projects/{project_name}/deployments
```

### Create Deployment
```
POST /accounts/{account_id}/pages/projects/{project_name}/deployments
```

Content-Type: multipart/form-data

---

## Zone Settings API

### List All Settings
```
GET /zones/{zone_id}/settings
```

### Get Setting
```
GET /zones/{zone_id}/settings/{setting_name}
```

### Update Setting
```
PATCH /zones/{zone_id}/settings/{setting_name}
```

Body:
```json
{
  "value": "setting_value"
}
```

### Common Settings

| Setting | Values |
|---------|--------|
| `always_online` | on, off |
| `always_use_https` | on, off |
| `automatic_https_rewrites` | on, off |
| `browser_cache_ttl` | 0, 30, 60, 120, ... 31536000 |
| `browser_check` | on, off |
| `cache_level` | bypass, basic, simplified, aggressive, cache_everything |
| `development_mode` | on, off |
| `email_obfuscation` | on, off |
| `hotlink_protection` | on, off |
| `ip_geolocation` | on, off |
| `minify` | {css: on/off, html: on/off, js: on/off} |
| `mirage` | on, off |
| `mobile_redirect` | {status: on/off, mobile_subdomain: "m"} |
| `opportunistic_encryption` | on, off |
| `polish` | off, lossless, lossy |
| `rocket_loader` | on, off, manual |
| `security_level` | off, essentially_off, low, medium, high, under_attack |
| `ssl` | off, flexible, full, strict |
| `tls_1_3` | on, off, zrt |
| `websockets` | on, off |

---

## Analytics API

### Get Zone Analytics
```
GET /zones/{zone_id}/analytics/dashboard
```

Query Parameters:
- `since` - Start time (ISO 8601 or relative: -1440 for last 24 hours in minutes)
- `until` - End time
- `continuous` - true/false

### Get DNS Analytics
```
GET /zones/{zone_id}/dns_analytics/report
```

### Get Firewall Analytics
```
GET /zones/{zone_id}/firewall/analytics
```

---

## Accounts API

### List Accounts
```
GET /accounts
```

### Get Account Details
```
GET /accounts/{account_id}
```

### List Account Members
```
GET /accounts/{account_id}/members
```

---

## User API

### Get User Details
```
GET /user
```

### Verify Token
```
GET /user/tokens/verify
```

---

## Error Codes

| Code | Description |
|------|-------------|
| 1000 | Invalid user |
| 1001 | Invalid request |
| 1002 | Unauthorized |
| 1003 | Forbidden |
| 1004 | Not found |
| 1006 | Request was rate limited |
| 1007 | Invalid JSON |
| 1008 | Missing required field |
| 1009 | Invalid field value |
| 6003 | Invalid token |
| 6103 | Token missing permissions |
| 7003 | Zone not found |
| 7000 | DNS record not found |
| 81057 | DNS record already exists |

---

## Pagination

Use `page` and `per_page` query parameters:

```
GET /zones?page=1&per_page=50
```

Response includes `result_info`:
```json
{
  "result_info": {
    "page": 1,
    "per_page": 50,
    "total_pages": 3,
    "count": 50,
    "total_count": 142
  }
}
```

---

## Filtering

Many endpoints support filtering with query parameters:

```
GET /zones/{zone_id}/dns_records?type=A&name=subdomain
```

Some endpoints support expression-based filtering:

```
GET /zones/{zone_id}/firewall/rules?filter=(action eq "block")
```

---

## Webhooks (Notifications)

### List Notification Destinations
```
GET /accounts/{account_id}/alerting/v3/destinations/webhooks
```

### Create Webhook
```
POST /accounts/{account_id}/alerting/v3/destinations/webhooks
```

Body:
```json
{
  "name": "My Webhook",
  "url": "https://example.com/webhook",
  "secret": "optional_secret"
}
```

---

## Best Practices

1. **Use API Tokens** with minimal required permissions
2. **Handle rate limits** gracefully with exponential backoff
3. **Cache zone IDs** to avoid repeated lookups
4. **Use pagination** for large result sets
5. **Check success field** in all responses
6. **Log API errors** with full response for debugging
7. **Use HTTPS** for all API calls
8. **Validate input** before sending to API
