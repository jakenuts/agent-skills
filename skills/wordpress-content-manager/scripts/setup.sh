#!/usr/bin/env bash
set -euo pipefail

PROFILE="${WP_PROFILE:-example-blog}"

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE_PATH="${SKILL_DIR}/profiles/${PROFILE}.json"

if [[ ! -f "$PROFILE_PATH" ]]; then
  echo "Profile not found: $PROFILE_PATH" >&2
  exit 2
fi

if ! command -v node >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Node.js not found. Installing Node.js via brew..." >&2
    brew install node
  elif command -v apt-get >/dev/null 2>&1; then
    echo "Node.js not found. Installing Node.js via apt-get..." >&2
    if command -v sudo >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y nodejs npm
    else
      apt-get update
      apt-get install -y nodejs npm
    fi
  else
    echo "Node.js 16+ is required but not found. Install Node.js and ensure 'node' is on PATH." >&2
    exit 2
  fi
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js install did not update PATH in this session. Restart your shell and rerun setup." >&2
  exit 2
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required but not found. Install Node.js 16+ (includes npm) and rerun setup." >&2
  exit 2
fi

NODE_VERSION="$(node -v | sed 's/^v//')"
NODE_MAJOR="${NODE_VERSION%%.*}"
if [[ "${NODE_MAJOR:-0}" -lt 16 ]]; then
  echo "Node.js $NODE_VERSION found, but 16+ is required. Upgrade Node.js and rerun setup." >&2
  exit 2
fi

CLI_PATH="${WP_CLI_PATH:-}"
if [[ -z "$CLI_PATH" ]]; then
  CLI_PATH="$(node -e "const fs=require('fs');const p=JSON.parse(fs.readFileSync('${PROFILE_PATH}','utf8'));process.stdout.write(p.cli_path||'');")"
fi

if [[ -z "$CLI_PATH" || ! -d "$CLI_PATH" ]]; then
  ALT_PATH="${SKILL_DIR}/tools/blog-wordpress"
  if [[ -d "$ALT_PATH" ]]; then
    CLI_PATH="$ALT_PATH"
  fi
fi

if [[ -z "$CLI_PATH" || ! -d "$CLI_PATH" ]]; then
  echo "WordPress CLI path not found. Set WP_CLI_PATH or update profile cli_path (you can place it under tools/blog-wordpress in this skill)." >&2
  exit 2
fi

missing=()
if [[ -z "${WP_USERNAME:-}" ]]; then
  missing+=("WP_USERNAME")
fi
if [[ -z "${WP_APP_PASSWORD:-}" ]]; then
  missing+=("WP_APP_PASSWORD")
fi
if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "Missing required environment variables: ${missing[*]}. Set them and rerun setup." >&2
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
