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

$sharedDotnetTools = Join-Path $PSScriptRoot '..\..\_shared\scripts\dotnet-tools.ps1'
if (-not (Test-Path $sharedDotnetTools)) {
    Write-Err "Shared dotnet tools helper not found: $sharedDotnetTools"
    exit 2
}

. $sharedDotnetTools

function Install-Tool {
    Install-DotnetTool -PackageId $packageId -Version $version -ToolsDir $toolsDir -CommandName $command -Channel $channel
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
Ensure-DotnetRuntime -Channel $channel
Ensure-DotnetToolsEnv
Install-Tool
Check-Env
