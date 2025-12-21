# Profiles

Profiles define site-specific defaults for WordPress connections. The skill loads a profile by name and applies any overrides from environment variables.

## Location

`profiles/<profile-name>.json`

## Example

```json
{
  "name": "gbase-blog",
  "site_url": "https://blog.gbase.com",
  "api_url": "https://blog.gbase.com/wp-json/wp/v2",
  "cli_path": "X:\\core\\tools\\blog-wordpress",
  "env": {
    "username": "WP_USERNAME",
    "app_password": "WP_APP_PASSWORD"
  }
}
```

## Fields

- `name` (string): Profile name.
- `site_url` (string): WordPress site base URL.
- `api_url` (string): WordPress REST API base URL.
- `cli_path` (string): Path to the `blog-wordpress` CLI folder.
- `env.username` (string): Env var name for the WordPress username.
- `env.app_password` (string): Env var name for the WordPress Application Password.

## Overrides

These environment variables take precedence over profile values:

- `WP_SITE_URL`
- `WP_API_URL`
- `WP_CLI_PATH`
- `WP_USERNAME`
- `WP_APP_PASSWORD`

## Cross-Platform Note

If the `cli_path` in a profile is Windows-specific, set `WP_CLI_PATH` on Linux containers to the correct location where the CLI was copied.
