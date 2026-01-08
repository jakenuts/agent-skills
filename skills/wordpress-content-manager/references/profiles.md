# Profiles

Profiles define site-specific defaults for WordPress connections. The skill loads a profile by name and applies any overrides from environment variables.

## Location

`profiles/<profile-name>.json`

## Example

```json
{
  "name": "example-blog",
  "site_url": "https://blog.example.com",
  "api_url": "https://blog.example.com/wp-json/wp/v2",
  "cli_path": null,
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
- `cli_path` (string|null): Path to the `blog-wordpress` CLI folder. Set to `null` if using `WP_CLI_PATH` env var.
- `env.username` (string): Env var name for the WordPress username.
- `env.app_password` (string): Env var name for the WordPress Application Password.

## Overrides

These environment variables take precedence over profile values:

- `WP_SITE_URL`
- `WP_API_URL`
- `WP_CLI_PATH`
- `WP_USERNAME`
- `WP_APP_PASSWORD`

## Creating Your Own Profile

1. Copy `example-blog.json` to `your-site.json`
2. Update the URLs to match your WordPress site
3. Set `cli_path` to the location of your WordPress CLI, or leave as `null` and set `WP_CLI_PATH`
4. Use `--profile your-site` or set `WP_PROFILE=your-site`
