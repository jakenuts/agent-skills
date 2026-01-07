<#
.SYNOPSIS
    Deploy Agent Skills to installed agent skill directories.
.DESCRIPTION
    Copies skill folders to Claude Code and/or Codex CLI skill locations.
    Dependencies are installed later by the skills themselves.
.PARAMETER Force
    Overwrite existing skills.
.PARAMETER DryRun
    Show what would be deployed without making changes.
#>

param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeployScript = Join-Path $ScriptDir 'scripts/deploy.ps1'

function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok { param($msg) Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "   WARN: $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "   ERROR: $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "   $msg" -ForegroundColor Gray }
function Write-DryRun { param($msg) Write-Host "   [DRY RUN] $msg" -ForegroundColor DarkGray }

if (-not (Test-Path $DeployScript)) {
    Write-Err "Deploy script not found: $DeployScript"
    exit 1
}

$targets = @()
$claudeRoot = Join-Path $env:USERPROFILE '.claude'
$codexRoot = Join-Path $env:USERPROFILE '.codex'

if (Get-Command claude -ErrorAction SilentlyContinue -CommandType Application,Alias) {
    $targets += 'claude'
} elseif (Test-Path $claudeRoot) {
    $targets += 'claude'
}

if (Get-Command codex -ErrorAction SilentlyContinue -CommandType Application,Alias) {
    $targets += 'codex'
} elseif (Test-Path $codexRoot) {
    $targets += 'codex'
}

if ($targets.Count -eq 0) {
    Write-Warn "No supported agents detected."
    Write-Info "Expected commands: claude, codex"
    Write-Info "Expected directories: $claudeRoot or $codexRoot"
    exit 1
}

Write-Step "Deploying skills"
Write-Info "Detected targets: $($targets -join ', ')"

foreach ($target in $targets) {
    $invokeParams = @{ Target = $target }
    if ($Force) { $invokeParams.Force = $true }
    if ($DryRun) { $invokeParams.DryRun = $true }

    if ($DryRun) {
        $flags = @()
        if ($Force) { $flags += '-Force' }
        if ($DryRun) { $flags += '-DryRun' }
        Write-DryRun "Would run: $DeployScript -Target $target $($flags -join ' ')"
    }
    & $DeployScript @invokeParams
}

if ($DryRun) {
    Write-Ok "Dry run complete. No changes were made."
} else {
    Write-Ok "Deployment complete. Restart your agent to load new skills."
}
