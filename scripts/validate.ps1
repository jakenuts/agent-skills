<#
.SYNOPSIS
    Validate Agent Skills for format compliance.

.DESCRIPTION
    Checks skill directories for required files and validates
    SKILL.md frontmatter against the Agent Skills specification.

.PARAMETER Skill
    Name of a specific skill to validate. If omitted, validates all skills.

.PARAMETER SkillsPath
    Path to the skills directory. Defaults to ../skills relative to script location.

.EXAMPLE
    .\validate.ps1
    Validate all skills.

.EXAMPLE
    .\validate.ps1 -Skill solarwinds-logs
    Validate a specific skill.
#>

param(
    [string]$Skill,
    [string]$SkillsPath
)

$ErrorActionPreference = 'Stop'

# Determine paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SkillsPath) {
    $SkillsPath = Join-Path (Split-Path -Parent $ScriptDir) 'skills'
}

# Validation results
$Errors = @()
$Warnings = @()
$Validated = 0

function Test-SkillName {
    param([string]$Name)
    # name: 1-64 characters, lowercase alphanumeric and hyphens only
    # Cannot start/end with hyphens or contain consecutive hyphens
    if ($Name.Length -lt 1 -or $Name.Length -gt 64) {
        return $false
    }
    if ($Name -notmatch '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$') {
        return $false
    }
    if ($Name -match '--') {
        return $false
    }
    return $true
}

function Get-Frontmatter {
    param([string]$Content)

    if ($Content -notmatch '^---\s*\r?\n') {
        return $null
    }

    $parts = $Content -split '---\s*\r?\n', 3
    if ($parts.Count -lt 3) {
        return $null
    }

    $yaml = $parts[1]
    $result = @{}

    foreach ($line in $yaml -split '\r?\n') {
        if ($line -match '^\s*([^:]+):\s*(.*)$') {
            $key = $Matches[1].Trim()
            $value = $Matches[2].Trim()
            # Remove quotes if present
            if ($value.StartsWith('"') -and $value.EndsWith('"')) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            elseif ($value.StartsWith("'") -and $value.EndsWith("'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $result[$key] = $value
        }
    }

    return $result
}

function Validate-Skill {
    param(
        [string]$SkillDir,
        [string]$SkillName
    )

    $localErrors = @()
    $localWarnings = @()

    # Check SKILL.md exists
    $skillFile = Join-Path $SkillDir 'SKILL.md'
    if (-not (Test-Path $skillFile)) {
        $localErrors += "SKILL.md not found"
        return @{ Errors = $localErrors; Warnings = $localWarnings }
    }

    $content = Get-Content $skillFile -Raw

    # Parse frontmatter
    $frontmatter = Get-Frontmatter -Content $content
    if ($null -eq $frontmatter) {
        $localErrors += "Invalid or missing YAML frontmatter"
        return @{ Errors = $localErrors; Warnings = $localWarnings }
    }

    # Check required fields
    if (-not $frontmatter.ContainsKey('name')) {
        $localErrors += "Missing required field: name"
    } else {
        $name = $frontmatter['name']

        # Validate name format
        if (-not (Test-SkillName -Name $name)) {
            $localErrors += "Invalid name format: '$name' (must be 1-64 lowercase alphanumeric chars with hyphens)"
        }

        # Check name matches directory
        if ($name -ne $SkillName) {
            $localWarnings += "Skill name '$name' does not match directory name '$SkillName'"
        }
    }

    if (-not $frontmatter.ContainsKey('description')) {
        $localErrors += "Missing required field: description"
    } else {
        $desc = $frontmatter['description']
        if ($desc.Length -lt 1) {
            $localErrors += "Description cannot be empty"
        }
        if ($desc.Length -gt 1024) {
            $localErrors += "Description exceeds 1024 characters"
        }
    }

    # Check for body content
    $bodyMatch = $content -match '---[\s\S]*?---\s*\r?\n(.+)'
    if (-not $bodyMatch -or $Matches[1].Trim().Length -eq 0) {
        $localWarnings += "SKILL.md has no body content"
    }

    return @{ Errors = $localErrors; Warnings = $localWarnings }
}

# Get skills to validate
if ($Skill) {
    $SkillDirs = @(Join-Path $SkillsPath $Skill)
    if (-not (Test-Path $SkillDirs[0])) {
        Write-Error "Skill not found: $Skill"
        exit 1
    }
} else {
    $SkillDirs = Get-ChildItem -Path $SkillsPath -Directory | Select-Object -ExpandProperty FullName
}

Write-Host "Agent Skills Validator" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan
Write-Host ""

foreach ($skillDir in $SkillDirs) {
    $skillName = Split-Path -Leaf $skillDir

    Write-Host "Validating: $skillName" -ForegroundColor Yellow

    $result = Validate-Skill -SkillDir $skillDir -SkillName $skillName

    if ($result.Errors.Count -eq 0 -and $result.Warnings.Count -eq 0) {
        Write-Host "  OK" -ForegroundColor Green
        $Validated++
    } else {
        foreach ($err in $result.Errors) {
            Write-Host "  ERROR: $err" -ForegroundColor Red
            $Errors += "${skillName}: $err"
        }
        foreach ($warn in $result.Warnings) {
            Write-Host "  WARNING: $warn" -ForegroundColor DarkYellow
            $Warnings += "${skillName}: $warn"
        }
        if ($result.Errors.Count -eq 0) {
            $Validated++
        }
    }
}

Write-Host ""
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "-------" -ForegroundColor Cyan
Write-Host "Skills validated: $Validated"
$errColor = if ($Errors.Count -gt 0) { 'Red' } else { 'Green' }
$warnColor = if ($Warnings.Count -gt 0) { 'Yellow' } else { 'Green' }
Write-Host "Errors: $($Errors.Count)" -ForegroundColor $errColor
Write-Host "Warnings: $($Warnings.Count)" -ForegroundColor $warnColor

if ($Errors.Count -gt 0) {
    exit 1
}
