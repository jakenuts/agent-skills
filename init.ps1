<#
.SYNOPSIS
    Initialize the Agent Skills toolkit on a fresh machine.

.DESCRIPTION
    Single entrypoint for setting up the Agent Skills toolkit:
    - Checks prerequisites (.NET SDK)
    - Installs required CLI tools (e.g., logs)
    - Deploys skills to agent platforms (Claude Code, Codex CLI)
    - Validates the installation

.PARAMETER Target
    Agent platform(s) to deploy skills to: 'claude', 'codex', or 'all'. Default: 'all'

.PARAMETER SkipTools
    Skip tool installation (only deploy skills).

.PARAMETER SkipSkills
    Skip skill deployment (only install tools).

.PARAMETER Force
    Overwrite existing skills and reinstall tools.

.PARAMETER DryRun
    Show what would be done without making changes.

.PARAMETER ToolSource
    Override tool source: 'local' (default), 'nuget-private', 'github-packages'

.EXAMPLE
    .\init.ps1
    Full initialization with all defaults.

.EXAMPLE
    .\init.ps1 -Target claude -Force
    Initialize for Claude Code only, overwriting existing.

.EXAMPLE
    .\init.ps1 -SkipTools
    Deploy skills only, assume tools are already installed.

.EXAMPLE
    .\init.ps1 -DryRun
    Preview what would be installed/deployed.
#>

param(
    [ValidateSet('claude', 'codex', 'all')]
    [string]$Target = 'all',

    [switch]$SkipTools,
    [switch]$SkipSkills,
    [switch]$Force,
    [switch]$DryRun,

    [ValidateSet('local', 'nuget-private', 'github-packages')]
    [string]$ToolSource = 'local'
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Colors helper
function Write-Step { param($msg) Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-Ok { param($msg) Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "   WARN: $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "   ERROR: $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "   $msg" -ForegroundColor Gray }
function Write-DryRun { param($msg) Write-Host "   [DRY RUN] $msg" -ForegroundColor DarkGray }

# Banner
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Agent Skills Toolkit - Initialization" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load config
$configPath = Join-Path $ScriptDir 'config.json'
if (-not (Test-Path $configPath)) {
    Write-Err "config.json not found at $configPath"
    exit 1
}
$config = Get-Content $configPath -Raw | ConvertFrom-Json

Write-Host "Platform: Windows" -ForegroundColor Gray
Write-Host "Tool source: $ToolSource" -ForegroundColor Gray
Write-Host "Target agents: $Target" -ForegroundColor Gray
if ($DryRun) { Write-Host "Mode: DRY RUN" -ForegroundColor Yellow }
Write-Host ""

# ====================
# Step 1: Prerequisites
# ====================
Write-Step "Checking prerequisites..."

# Check .NET SDK (required for dotnet tool install)
$dotnetVersion = $null
try {
    $dotnetVersion = (dotnet --version 2>$null)
    if ($dotnetVersion) {
        Write-Ok ".NET SDK $dotnetVersion"
    }
} catch {}

if (-not $dotnetVersion) {
    Write-Err ".NET SDK not found. Please install from https://dotnet.microsoft.com/download"
    exit 1
}

# Check .NET version is 10.0+
$majorVersion = [int]($dotnetVersion.Split('.')[0])
if ($majorVersion -lt 10) {
    Write-Err ".NET SDK $dotnetVersion is too old. Version 10.0+ required."
    Write-Info "Tools target .NET 10. The .NET 10 SDK can also build .NET 8/9 projects."
    exit 1
}

Write-Info "Tools target .NET 10 (SDK also builds .NET 8/9 projects)"

# ====================
# Step 2: Install Tools
# ====================
if (-not $SkipTools) {
    Write-Step "Installing CLI tools..."

    foreach ($toolName in $config.tools.PSObject.Properties.Name) {
        $tool = $config.tools.$toolName
        $packageId = $tool.packageId
        $version = $tool.version
        $command = $tool.command

        Write-Info "Tool: $toolName ($packageId v$version)"

        # Check if already installed
        $installed = $null
        try {
            $toolList = dotnet tool list --global 2>$null | Select-String $packageId
            if ($toolList) {
                $installed = $toolList.ToString()
            }
        } catch {}

        if ($installed -and -not $Force) {
            Write-Ok "Already installed: $installed"

            # Verify command works
            try {
                $null = & $command --help 2>$null
                Write-Ok "Command '$command' is functional"
            } catch {
                Write-Warn "Command '$command' not responding, consider -Force reinstall"
            }
            continue
        }

        # Determine source
        $sourceConfig = $tool.sources.$ToolSource
        if (-not $sourceConfig) {
            Write-Err "Source '$ToolSource' not configured for tool '$toolName'"
            exit 1
        }

        # Build install command
        $installArgs = @('tool', 'install', '--global', $packageId, '--version', $version)

        if ($sourceConfig.type -eq 'local') {
            $localPath = Join-Path $ScriptDir $sourceConfig.path
            if (-not (Test-Path $localPath)) {
                Write-Err "Local tool path not found: $localPath"
                exit 1
            }
            $installArgs += @('--add-source', $localPath)
        }
        elseif ($sourceConfig.type -eq 'nuget') {
            $installArgs += @('--add-source', $sourceConfig.url)
        }

        if ($Force) {
            # Uninstall first if forcing
            if ($DryRun) {
                Write-DryRun "Would uninstall $packageId"
            } else {
                Write-Info "Uninstalling existing $packageId..."
                try {
                    dotnet tool uninstall --global $packageId 2>$null | Out-Null
                } catch {}
            }
        }

        # Install
        if ($DryRun) {
            Write-DryRun "Would run: dotnet $($installArgs -join ' ')"
        } else {
            Write-Info "Installing $packageId..."
            $result = & dotnet @installArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Err "Failed to install $packageId"
                Write-Err $result
                exit 1
            }
            Write-Ok "Installed $packageId v$version"
        }

        # Verify command
        if (-not $DryRun) {
            try {
                $null = & $command --help 2>$null
                Write-Ok "Command '$command' is functional"
            } catch {
                Write-Warn "Command '$command' installed but not responding. You may need to restart your terminal."
            }
        }

        # Check required environment variables
        if ($tool.requiredEnvVars) {
            Write-Info "Checking required environment variables..."
            foreach ($envVar in $tool.requiredEnvVars) {
                $value = [Environment]::GetEnvironmentVariable($envVar)
                if ($value) {
                    Write-Ok "$envVar is set"
                } else {
                    Write-Warn "$envVar is not set. The tool may not function until this is configured."
                }
            }
        }
    }
}

# ====================
# Step 3: Deploy Skills
# ====================
if (-not $SkipSkills) {
    Write-Step "Deploying skills..."

    $skillsPath = Join-Path $ScriptDir 'skills'
    $skills = Get-ChildItem -Path $skillsPath -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName 'SKILL.md')
    }

    if ($skills.Count -eq 0) {
        Write-Warn "No skills found in $skillsPath"
    } else {
        Write-Info "Found $($skills.Count) skill(s): $($skills.Name -join ', ')"
    }

    # Determine targets
    $deployTargets = @()
    if ($Target -eq 'all') {
        $deployTargets = @('claude', 'codex')
    } else {
        $deployTargets = @($Target)
    }

    foreach ($agentName in $deployTargets) {
        $agentConfig = $config.agents.$agentName
        $targetPath = $agentConfig.skillsPath.windows -replace '%USERPROFILE%', $env:USERPROFILE

        Write-Info "Deploying to $agentName ($targetPath)..."

        if ($DryRun) {
            Write-DryRun "Would create directory: $targetPath"
        } else {
            if (-not (Test-Path $targetPath)) {
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                Write-Ok "Created $targetPath"
            }
        }

        foreach ($skill in $skills) {
            $skillDest = Join-Path $targetPath $skill.Name

            if ((Test-Path $skillDest) -and -not $Force) {
                Write-Info "Skipped $($skill.Name) (exists, use -Force to overwrite)"
                continue
            }

            if ($DryRun) {
                Write-DryRun "Would copy $($skill.Name) to $targetPath"
            } else {
                if (Test-Path $skillDest) {
                    Remove-Item -Path $skillDest -Recurse -Force
                }
                Copy-Item -Path $skill.FullName -Destination $skillDest -Recurse
                Write-Ok "Deployed $($skill.Name)"
            }
        }
    }
}

# ====================
# Step 4: Validation
# ====================
Write-Step "Validating installation..."

$validationErrors = 0

# Validate tools
if (-not $SkipTools -and -not $DryRun) {
    foreach ($toolName in $config.tools.PSObject.Properties.Name) {
        $tool = $config.tools.$toolName
        $command = $tool.command

        try {
            $null = & $command --help 2>$null
            Write-Ok "Tool '$command' responds"
        } catch {
            Write-Err "Tool '$command' not functional"
            $validationErrors++
        }
    }
}

# Validate skills deployment
if (-not $SkipSkills -and -not $DryRun) {
    $deployTargets = if ($Target -eq 'all') { @('claude', 'codex') } else { @($Target) }

    foreach ($agentName in $deployTargets) {
        $agentConfig = $config.agents.$agentName
        $targetPath = $agentConfig.skillsPath.windows -replace '%USERPROFILE%', $env:USERPROFILE

        if (Test-Path $targetPath) {
            $deployedSkills = Get-ChildItem -Path $targetPath -Directory | Where-Object {
                Test-Path (Join-Path $_.FullName 'SKILL.md')
            }
            Write-Ok "${agentName}: $($deployedSkills.Count) skill(s) deployed"
        } else {
            Write-Warn "${agentName}: Skills directory not found"
        }
    }
}

# ====================
# Summary
# ====================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "  Dry run complete - no changes made" -ForegroundColor Yellow
} elseif ($validationErrors -gt 0) {
    Write-Host "  Initialization completed with warnings" -ForegroundColor Yellow
} else {
    Write-Host "  Initialization complete!" -ForegroundColor Green
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $DryRun) {
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Restart your terminal to ensure PATH updates take effect" -ForegroundColor Gray
    Write-Host "  2. Set SOLARWINDS_API_TOKEN if not already configured" -ForegroundColor Gray
    Write-Host "  3. Restart Claude Code or Codex CLI to load skills" -ForegroundColor Gray
    Write-Host "  4. Test with: logs --help" -ForegroundColor Gray
    Write-Host ""
}

exit $validationErrors
