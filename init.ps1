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
$AgentsPath = Join-Path $ScriptDir 'agents'

# Target definitions
$Targets = @{
    'claude' = @{
        'skills_path' = Join-Path $env:USERPROFILE '.claude\skills'
        'agents_path' = Join-Path $env:USERPROFILE '.claude\agents'
        'name' = 'Claude Code'
    }
    'codex' = @{
        'skills_path' = Join-Path $env:USERPROFILE '.codex\skills'
        'agents_path' = Join-Path $env:USERPROFILE '.codex\agents'
        'name' = 'Codex CLI'
    }
}

# Validate source directories
if (-not (Test-Path $SkillsPath)) {
    Write-Err "Skills directory not found: $SkillsPath"
    exit 1
}

$HasAgents = Test-Path $AgentsPath
if (-not $HasAgents) {
    Write-Warn "Agents directory not found: $AgentsPath (skipping agents deployment)"
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
}

# Find agent definition files (*.md in agents folder and subdirectories)
$Agents = @()
if ($HasAgents) {
    $Agents = Get-ChildItem -Path $AgentsPath -Filter "*.md" -Recurse
}

if ($Skills.Count -eq 0 -and $Agents.Count -eq 0) {
    Write-Warn "No skills or agents found to deploy"
    exit 0
}

Write-Step "Found content to deploy"
if ($Skills.Count -gt 0) {
    Write-Info "$($Skills.Count) skill(s):"
    foreach ($skill in $Skills) {
        Write-Info "  - $($skill.Name)"
    }
}
if ($Agents.Count -gt 0) {
    Write-Info "$($Agents.Count) agent definition(s)"
}

Write-Info ""
Write-Info "Detected targets: $($DetectedTargets -join ', ')"

# Deploy functions
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

function Deploy-Agents {
    param($AgentsSource, $TargetPath)

    if ($DryRun) {
        Write-DryRun "Would sync agents directory structure"
    } else {
        if (-not (Test-Path $TargetPath)) {
            New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
        }

        # Copy entire agents directory structure, preserving hierarchy
        $agentFiles = Get-ChildItem -Path $AgentsSource -Filter "*.md" -Recurse
        $deployed = 0
        foreach ($agentFile in $agentFiles) {
            # Calculate relative path from agents source
            $relativePath = $agentFile.FullName.Substring($AgentsSource.Length + 1)
            $destPath = Join-Path $TargetPath $relativePath
            $destDir = Split-Path -Parent $destPath

            # Create destination directory if needed
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            # Copy or update the file
            if ((Test-Path $destPath) -and -not $Force) {
                # Skip existing files unless -Force is specified
                continue
            }

            Copy-Item -Path $agentFile.FullName -Destination $destPath -Force
            $deployed++
        }

        if ($deployed -gt 0) {
            Write-Ok "Deployed $deployed agent definition(s)"
        } else {
            Write-Info "All agent definitions up to date"
        }
    }
}

# Deploy to each target
foreach ($targetKey in $DetectedTargets) {
    $targetInfo = $Targets[$targetKey]
    $skillsTargetPath = $targetInfo['skills_path']
    $agentsTargetPath = $targetInfo['agents_path']
    $targetName = $targetInfo['name']

    Write-Step "Deploying to $targetName"

    # Deploy skills
    if ($Skills.Count -gt 0) {
        Write-Info "Skills path: $skillsTargetPath"

        if ($DryRun) {
            Write-DryRun "Would create directory: $skillsTargetPath"
        } else {
            if (-not (Test-Path $skillsTargetPath)) {
                New-Item -ItemType Directory -Path $skillsTargetPath -Force | Out-Null
                Write-Ok "Created directory: $skillsTargetPath"
            }
        }

        foreach ($skill in $Skills) {
            Deploy-Skill -SkillName $skill.Name -SkillSource $skill.FullName -TargetPath $skillsTargetPath
        }
    }

    # Deploy agents
    if ($HasAgents) {
        Write-Info "Agents path: $agentsTargetPath"
        Deploy-Agents -AgentsSource $AgentsPath -TargetPath $agentsTargetPath
    }
}

Write-Step "Complete"
if ($DryRun) {
    Write-Ok "Dry run complete. No changes were made."
} else {
    Write-Ok "Deployment complete. Restart your agent to load new skills."
}
