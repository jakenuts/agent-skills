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
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Node.js not found. Installing Node.js LTS via winget..." -ForegroundColor Yellow
        winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements --silent | Out-Host
    } else {
        Write-Error "Node.js 16+ is required but not found. Install Node.js and ensure 'node' is on PATH."
        exit 2
    }
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Error "Node.js install did not update PATH in this session. Restart your terminal and rerun setup."
    exit 2
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Error "npm is required but not found. Install Node.js 16+ (includes npm) and rerun setup."
    exit 2
}

$nodeVersion = (& node --version) -replace '^v', ''
$nodeMajor = [int]($nodeVersion.Split('.')[0])
if ($nodeMajor -lt 16) {
    Write-Error "Node.js $nodeVersion found, but 16+ is required. Upgrade Node.js and rerun setup."
    exit 2
}

$profile = Get-Content -Raw -Path $profilePath | ConvertFrom-Json

$cliPath = $env:WP_CLI_PATH
if ([string]::IsNullOrWhiteSpace($cliPath)) {
    $cliPath = $profile.cli_path
}

if ([string]::IsNullOrWhiteSpace($cliPath) -or -not (Test-Path $cliPath)) {
    $altPath = Join-Path $skillDir 'tools\blog-wordpress'
    if (Test-Path $altPath) {
        $cliPath = $altPath
    }
}

if ([string]::IsNullOrWhiteSpace($cliPath) -or -not (Test-Path $cliPath)) {
    Write-Error "WordPress CLI path not found. Set WP_CLI_PATH or update profile cli_path (you can place it under tools/blog-wordpress in this skill)."
    exit 2
}

$missing = @()
if ([string]::IsNullOrWhiteSpace($env:WP_USERNAME)) { $missing += 'WP_USERNAME' }
if ([string]::IsNullOrWhiteSpace($env:WP_APP_PASSWORD)) { $missing += 'WP_APP_PASSWORD' }
if ($missing.Count -gt 0) {
    Write-Error "Missing required environment variables: $($missing -join ', '). Set them and rerun setup."
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
