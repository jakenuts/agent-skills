param(
    [string]$Profile = $env:WP_PROFILE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Profile)) {
    $Profile = "gbase-blog"
}

$skillDir = Split-Path -Parent $PSScriptRoot
$profilePath = Join-Path $skillDir "profiles\$Profile.json"

if (-not (Test-Path $profilePath)) {
    Write-Error "Profile not found: $profilePath"
    exit 2
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js is required but not found. Install Node.js 16+ and ensure 'node' is on PATH."
    exit 2
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Error "npm is required but not found. Install Node.js 16+ (includes npm)."
    exit 2
}

$profile = Get-Content -Raw -Path $profilePath | ConvertFrom-Json

$cliPath = $env:WP_CLI_PATH
if ([string]::IsNullOrWhiteSpace($cliPath)) {
    $cliPath = $profile.cli_path
}

if ([string]::IsNullOrWhiteSpace($cliPath) -or -not (Test-Path $cliPath)) {
    Write-Error "WordPress CLI path not found. Set WP_CLI_PATH or update profile cli_path."
    exit 2
}

Push-Location $cliPath
try {
    if (Test-Path "package-lock.json") {
        npm ci --no-audit --no-fund | Out-Host
    } else {
        npm install --no-audit --no-fund | Out-Host
    }

    npm run validate | Out-Host
} finally {
    Pop-Location
}
