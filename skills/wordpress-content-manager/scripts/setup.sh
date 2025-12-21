#!/usr/bin/env bash
set -euo pipefail

PROFILE="${WP_PROFILE:-gbase-blog}"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_PATH="${SKILL_DIR}/profiles/${PROFILE}.json"

if [[ ! -f "$PROFILE_PATH" ]]; then
  echo "Profile not found: $PROFILE_PATH" >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required but not found. Install Node.js 16+ and ensure 'node' is on PATH." >&2
  exit 2
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required but not found. Install Node.js 16+ (includes npm)." >&2
  exit 2
fi

CLI_PATH="${WP_CLI_PATH:-}"
if [[ -z "$CLI_PATH" ]]; then
  CLI_PATH="$(node -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync('${PROFILE_PATH}','utf8'));process.stdout.write(p.cli_path||'');")"
fi

if [[ -z "$CLI_PATH" || ! -d "$CLI_PATH" ]]; then
  echo "WordPress CLI path not found. Set WP_CLI_PATH or update profile cli_path." >&2
  exit 2
fi

pushd "$CLI_PATH" >/dev/null
if [[ -f "package-lock.json" ]]; then
  npm ci --no-audit --no-fund
else
  npm install --no-audit --no-fund
fi
npm run validate
popd >/dev/null
