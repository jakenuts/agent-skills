param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillDir = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $skillDir 'tools'
$packageId = 'DealerVision.SolarWindsLogSearch'
$version = '2.4.0'
$command = 'logs'
$channel = '10.0'

function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok { param($msg) Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "   WARN: $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "   ERROR: $msg" -ForegroundColor Red }

$sharedDotnet = Join-Path $PSScriptRoot '..\..\_shared\scripts\dotnet-env.ps1'
if (-not (Test-Path $sharedDotnet)) {
    Write-Err "Shared dotnet helper not found: $sharedDotnet"
    exit 2
}

. $sharedDotnet

function Install-Tool {
    if (-not (Test-Path $toolsDir)) {
        Write-Err "Tool package directory not found: $toolsDir"
        exit 2
    }

    $installed = $null
    try {
        $installed = dotnet tool list --global 2>$null | Select-String $packageId
    } catch {}

    if ($installed) {
        Write-Ok "Tool already installed: $packageId"
        return
    }

    Write-Step "Installing $packageId v$version"
    & dotnet tool install --global $packageId --version $version --add-source $toolsDir | Out-Null

    if (Get-Command $command -ErrorAction SilentlyContinue) {
        Write-Ok "Tool installed: $command"
    } else {
        Write-Warn "Tool installed but '$command' is not on PATH. Restart your shell and try again."
    }
}

function Check-Env {
    if ([string]::IsNullOrWhiteSpace($env:SOLARWINDS_API_TOKEN)) {
        Write-Warn "SOLARWINDS_API_TOKEN is not set"
        Write-Host "Set it with: `$env:SOLARWINDS_API_TOKEN = \"your-token-here\"" -ForegroundColor Gray
    } else {
        Write-Ok "SOLARWINDS_API_TOKEN is set"
    }
}

Write-Step "SolarWinds Logs Setup"
Ensure-Dotnet -Channel $channel
Install-Tool
Check-Env
