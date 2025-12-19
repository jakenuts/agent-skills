<#
.SYNOPSIS
    Deploy Agent Skills to Claude Code and/or Codex CLI.

.DESCRIPTION
    Copies skill files from the skills/ directory to the appropriate
    agent skill locations for Claude Code and Codex CLI.

.PARAMETER Target
    Target platform(s) to deploy to: 'claude', 'codex', or 'all'

.PARAMETER SkillsPath
    Path to the skills directory. Defaults to ../skills relative to script location.

.PARAMETER Force
    Overwrite existing skills without prompting.

.PARAMETER DryRun
    Show what would be deployed without making changes.

.EXAMPLE
    .\deploy.ps1 -Target claude
    Deploy skills to Claude Code only.

.EXAMPLE
    .\deploy.ps1 -Target all -Force
    Deploy to all platforms, overwriting existing skills.

.EXAMPLE
    .\deploy.ps1 -Target codex -DryRun
    Show what would be deployed to Codex CLI.
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('claude', 'codex', 'all')]
    [string]$Target,

    [string]$SkillsPath,

    [switch]$Force,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Determine script and skills paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SkillsPath) {
    $SkillsPath = Join-Path (Split-Path -Parent $ScriptDir) 'skills'
}

# Validate skills directory exists
if (-not (Test-Path $SkillsPath)) {
    Write-Error "Skills directory not found: $SkillsPath"
    exit 1
}

# Define target directories
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

# Determine which targets to deploy to
$DeployTargets = @()
if ($Target -eq 'all') {
    $DeployTargets = @('claude', 'codex')
} else {
    $DeployTargets = @($Target)
}

# Get list of skills
$Skills = Get-ChildItem -Path $SkillsPath -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName 'SKILL.md')
}

if ($Skills.Count -eq 0) {
    Write-Warning "No valid skills found in $SkillsPath"
    exit 0
}

Write-Host "Found $($Skills.Count) skill(s) to deploy:" -ForegroundColor Cyan
foreach ($skill in $Skills) {
    Write-Host "  - $($skill.Name)" -ForegroundColor Gray
}
Write-Host ""

# Deploy to each target
foreach ($targetKey in $DeployTargets) {
    $targetInfo = $Targets[$targetKey]
    $targetPath = $targetInfo['path']
    $targetName = $targetInfo['name']

    Write-Host "Deploying to $targetName ($targetPath)..." -ForegroundColor Yellow

    if ($DryRun) {
        Write-Host "  [DRY RUN] Would create directory: $targetPath" -ForegroundColor DarkGray
    } else {
        if (-not (Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            Write-Host "  Created directory: $targetPath" -ForegroundColor Green
        }
    }

    foreach ($skill in $Skills) {
        $skillSource = $skill.FullName
        $skillDest = Join-Path $targetPath $skill.Name

        if (Test-Path $skillDest) {
            if ($Force -or $DryRun) {
                if ($DryRun) {
                    Write-Host "  [DRY RUN] Would overwrite: $($skill.Name)" -ForegroundColor DarkGray
                } else {
                    Remove-Item -Path $skillDest -Recurse -Force
                    Copy-Item -Path $skillSource -Destination $skillDest -Recurse
                    Write-Host "  Updated: $($skill.Name)" -ForegroundColor Green
                }
            } else {
                Write-Host "  Skipped (exists): $($skill.Name) - use -Force to overwrite" -ForegroundColor DarkYellow
            }
        } else {
            if ($DryRun) {
                Write-Host "  [DRY RUN] Would copy: $($skill.Name)" -ForegroundColor DarkGray
            } else {
                Copy-Item -Path $skillSource -Destination $skillDest -Recurse
                Write-Host "  Installed: $($skill.Name)" -ForegroundColor Green
            }
        }
    }
    Write-Host ""
}

if ($DryRun) {
    Write-Host "Dry run complete. No changes were made." -ForegroundColor Cyan
} else {
    Write-Host "Deployment complete!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  - Restart Claude Code or Codex CLI to load the new skills" -ForegroundColor Gray
    Write-Host "  - Skills will be automatically discovered based on context" -ForegroundColor Gray
}
