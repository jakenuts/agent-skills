param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$skillDir = Split-Path -Parent $PSScriptRoot
$toolsDir = Join-Path $skillDir 'tools'
$packageId = 'DealerVision.SolarWindsLogSearch'
$version = '2.4.0'
$command = 'logs'
$channel = '10.0'
$installDir = Join-Path $env:USERPROFILE '.dotnet'

function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok { param($msg) Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "   WARN: $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "   ERROR: $msg" -ForegroundColor Red }

function Get-DotnetVersion {
    try {
        return (dotnet --version 2>$null)
    } catch {
        return $null
    }
}

function Ensure-Dotnet {
    $version = Get-DotnetVersion
    if ($version) {
        $major = [int]($version.Split('.')[0])
        if ($major -ge 10) {
            Write-Ok ".NET SDK $version detected"
            return
        }
        Write-Warn ".NET SDK $version found, but 10.0+ is required"
    } else {
        Write-Warn ".NET SDK not found"
    }

    Write-Step "Installing .NET SDK $channel"

    $installer = Join-Path $env:TEMP 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer
    & powershell -ExecutionPolicy Bypass -File $installer -Channel $channel -InstallDir $installDir | Out-Null

    $env:PATH = "$installDir;$installDir\tools;$env:PATH"
    Write-Ok ".NET SDK installed to $installDir"
    Write-Warn "Add $installDir and $installDir\tools to your PATH for future shells"
}

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
Ensure-Dotnet
Install-Tool
Check-Env
