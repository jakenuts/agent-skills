<#
.SYNOPSIS
    Deploy Agent Skills to installed agent skill directories.
.DESCRIPTION
    Copies skill folders to Claude Code and/or Codex CLI skill locations.
    Auto-detects which agents are installed. Skills handle their own
    dependency installation on first use.
.PARAMETER Force
    Overwrite existing skills.
.PARAMETER DryRun
    Show what would be deployed without making changes.
.EXAMPLE
    .\init.ps1
    Deploy to all detected agents.
.EXAMPLE
    .\init.ps1 -Force
    Deploy and overwrite existing skills.
.EXAMPLE
    .\init.ps1 -DryRun
    Show what would be deployed.
#>

param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Output helpers
function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok { param($msg) Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "   WARN: $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "   ERROR: $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "   $msg" -ForegroundColor Gray }
function Write-DryRun { param($msg) Write-Host "   [DRY RUN] $msg" -ForegroundColor DarkGray }

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkillsPath = Join-Path $ScriptDir 'skills'

# Target definitions
$Targets = @{
    'claude' = @{
        'path' = Join-Path $env:USERPROFILE '.claude\skills'
        'name' = 'Claude Code'
    }
    'codex' = @{
        'path' = Join-Path $env:USERPROFILE '.codex\skills'
        'name' = 'Codex CLI'
    }
}

# Validate skills directory
if (-not (Test-Path $SkillsPath)) {
    Write-Err "Skills directory not found: $SkillsPath"
    exit 1
}

# Detect installed agents
$DetectedTargets = @()
$claudeRoot = Join-Path $env:USERPROFILE '.claude'
$codexRoot = Join-Path $env:USERPROFILE '.codex'

if ((Get-Command claude -ErrorAction SilentlyContinue) -or (Test-Path $claudeRoot)) {
    $DetectedTargets += 'claude'
}
if ((Get-Command codex -ErrorAction SilentlyContinue) -or (Test-Path $codexRoot)) {
    $DetectedTargets += 'codex'
}

if ($DetectedTargets.Count -eq 0) {
    Write-Warn "No supported agents detected."
    Write-Info "Expected commands: claude, codex"
    Write-Info "Expected directories: $claudeRoot or $codexRoot"
    exit 1
}

# Find valid skills (directories with SKILL.md)
$Skills = Get-ChildItem -Path $SkillsPath -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName 'SKILL.md')
}

if ($Skills.Count -eq 0) {
    Write-Warn "No valid skills found in $SkillsPath"
    exit 0
}

Write-Step "Found $($Skills.Count) skill(s) to deploy"
foreach ($skill in $Skills) {
    Write-Info "- $($skill.Name)"
}

Write-Info ""
Write-Info "Detected targets: $($DetectedTargets -join ', ')"

# Deploy function
function Deploy-Skill {
    param($SkillName, $SkillSource, $TargetPath)
    
    $skillDest = Join-Path $TargetPath $SkillName

    if (Test-Path $skillDest) {
        if ($Force -or $DryRun) {
            if ($DryRun) {
                Write-DryRun "Would overwrite: $SkillName"
            } else {
                Remove-Item -Path $skillDest -Recurse -Force
                Copy-Item -Path $SkillSource -Destination $skillDest -Recurse
                Write-Ok "Updated: $SkillName"
            }
        } else {
            Write-Warn "Skipped (exists): $SkillName - use -Force to overwrite"
        }
    } else {
        if ($DryRun) {
            Write-DryRun "Would install: $SkillName"
        } else {
            Copy-Item -Path $SkillSource -Destination $skillDest -Recurse
            Write-Ok "Installed: $SkillName"
        }
    }
}

# Deploy to each target
foreach ($targetKey in $DetectedTargets) {
    $targetInfo = $Targets[$targetKey]
    $targetPath = $targetInfo['path']
    $targetName = $targetInfo['name']

    Write-Step "Deploying to $targetName"
    Write-Info "Path: $targetPath"

    if ($DryRun) {
        Write-DryRun "Would create directory: $targetPath"
    } else {
        if (-not (Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            Write-Ok "Created directory: $targetPath"
        }
    }

    foreach ($skill in $Skills) {
        Deploy-Skill -SkillName $skill.Name -SkillSource $skill.FullName -TargetPath $targetPath
    }
}

Write-Step "Complete"
if ($DryRun) {
    Write-Ok "Dry run complete. No changes were made."
} else {
    Write-Ok "Deployment complete. Restart your agent to load new skills."
}
