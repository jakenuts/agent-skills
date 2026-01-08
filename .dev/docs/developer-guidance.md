# Developer Guidance

## Objective

- Keep `init` fast and portable by only deploying skills.
- Let skills install their own dependencies when activated.
- Support multiple agents by detecting which CLIs are installed.
- Allow safe updates by redeploying skills with `--force`.

## Init Behavior

- `init` detects installed agents (Claude Code and/or Codex CLI) and deploys skills only.
- No runtime dependencies are installed at init time.
- Use `--force` to overwrite existing skills when you update the repo.
- If no agents are detected, install the agent CLI and rerun `init`.

## Skill Structure

- `SKILL.md` contains the activation instructions and staged setup.
- `scripts/` contains setup scripts and helper utilities.
- `references/` holds long-form docs and recipes.
- `tools/` holds skill-local tool packages (when applicable).

## Setup Model (Self-Contained)

Every skill that needs dependencies or configuration should provide a setup script inside the skill folder. The setup script should:

- Detect required dependencies (`dotnet --version`, `node --version`, etc.).
- Install missing dependencies using standard installers where possible.
- Install tool packages from the skill-local `tools/` directory.
- Verify the tool responds after installation.
- Check required environment variables and stop if missing before running API calls.

Setup scripts should be non-interactive, safe to rerun, and avoid global installs during `init`.

## Shared Dependencies

When multiple skills share a dependency (for example, .NET or Node.js):

- Check for the dependency first; only install if missing.
- Prefer global installs for tools that are shared across sessions (for example, `dotnet tool install --global`).
- If you need shared helper logic, place it under `scripts/shared/` within the skill so it is deployed with the skill.

## Tool Packaging

- Place `.nupkg` or other tool artifacts under `skills/<skill-name>/tools/`.
- Setup scripts should install from the skill-local path.
- The root `tools/` directory is legacy and should not be extended for new skills.

## Progressive Disclosure

- Metadata in frontmatter should be minimal but specific.
- Keep `SKILL.md` focused on activation/setup and core usage.
- Put long CLI references and recipes in `references/`.

## Examples

- `solarwinds-logs`:
  - Setup script installs .NET 10 if missing, installs `logs` from `tools/`, and checks `SOLARWINDS_API_TOKEN`.

- `wordpress-content-manager`:
  - Setup script installs Node.js if missing, installs npm dependencies, validates `WP_USERNAME`/`WP_APP_PASSWORD`, and prefers `tools/blog-wordpress` when available.

