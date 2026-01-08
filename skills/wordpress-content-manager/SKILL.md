---
name: wordpress-content-manager
description: WordPress content management via REST API for listing, searching, viewing, creating, updating, and deleting posts (including draft/scheduled/published) with tags and categories. Use when managing WordPress blog content via configurable site profiles. Requires Node.js and WordPress REST API credentials.
compatibility: Requires Node.js 16+ and npm. Uses WP_USERNAME and WP_APP_PASSWORD (Application Password) for authentication.
metadata:
  requires-setup: true
  default-profile: example-blog
---

# WordPress Content Manager

Manage WordPress posts in a site-agnostic way. Configure site profiles for your WordPress installations.

## Stage 1: Copy Only (No Install)

Ensure these are present on the target machine/container:
- This skill folder (copied by agent-skills deploy scripts)
- The WordPress CLI tool folder referenced by the active profile (for example `/path/to/blog-wordpress`) or `WP_CLI_PATH`
- Optional: place the CLI under `tools/blog-wordpress` in this skill and set `WP_CLI_PATH` accordingly
  - If `tools/blog-wordpress` exists, the setup script will prefer it automatically

Do not install Node or npm packages at this stage.

## Stage 2: Lazy Runtime Setup (Non-Interactive)

Run the setup script the first time the skill is activated. It verifies Node and npm, installs dependencies, and validates access.

If Node.js is missing, the setup script will attempt to install it using common package managers. If that fails, install Node.js 16+ manually and rerun setup.

### Windows (PowerShell)
```powershell
pwsh ~/.codex/skills/wordpress-content-manager/scripts/setup.ps1
```

### Linux/macOS
```bash
bash ~/.codex/skills/wordpress-content-manager/scripts/setup.sh
```

If you are using Claude Code, replace `~/.codex/skills` with `~/.claude/skills`.
Validation requires `WP_USERNAME` and `WP_APP_PASSWORD`; if missing, ask the user and stop before running setup.

## Profiles and Site Selection

Profiles live under `profiles/` in this skill. Select a profile with:
- `--profile <name>` flag
- or `WP_PROFILE=<name>` env var

If neither is set, the default profile `example-blog` is used.

See `references/profiles.md` for the profile format and overrides.

## Required Environment Variables

- `WP_USERNAME` (WordPress username)
- `WP_APP_PASSWORD` (WordPress Application Password)

Optional overrides:
- `WP_API_URL`
- `WP_SITE_URL`
- `WP_CLI_PATH` (path to `blog-wordpress` CLI folder)

## Commands

All commands are non-interactive and return JSON when `--json` is set.

### Describe Connection
```bash
node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs site info --json
```

### List or Search Posts
```bash
node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs posts list --status publish --search "guitar" --per_page 20 --page 1
```

### View a Post
```bash
node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs posts get 123 --json
```

### Create a Post (HTML or Markdown)
```bash
node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs posts create \
  --title "New Post" \
  --content-file ./post.md \
  --status draft \
  --categories 1,2 \
  --tags 5,7
```

### Schedule a Post
```bash
node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs posts create \
  --title "Scheduled Post" \
  --content "<p>HTML body</p>" \
  --status future \
  --date "2025-01-15T15:30:00"
```

### Update a Post
```bash
node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs posts update 123 \
  --title "Updated Title" \
  --status publish
```

### Delete a Post
```bash
node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs posts delete 123
```

### Bulk Delete (Dry-Run First)
```bash
node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs posts delete-many \
  --status draft \
  --search "test" \
  --dry-run

node ~/.codex/skills/wordpress-content-manager/scripts/wp-content.mjs posts delete-many \
  --status draft \
  --search "test" \
  --confirm
```

## Future Extensions (Out of Scope for v1)

- Plugin management
- YouTube automation or auto-content plugins

These can be added in a future version or by wrapping a more full-featured WordPress admin tool.
