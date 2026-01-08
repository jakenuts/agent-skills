param(
    [string]$Config = (Join-Path $PSScriptRoot 'test-config.json'),
    [string]$Scenario = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Info { param($msg) Write-Host "INFO: $msg" -ForegroundColor Gray }
function Write-Ok { param($msg) Write-Host "OK: $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "WARN: $msg" -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host "ERROR: $msg" -ForegroundColor Red }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Err "docker is not installed or not on PATH"
    exit 1
}

if (-not (Test-Path $Config)) {
    Write-Err "Config not found: $Config"
    Write-Info "Copy tests/containers/test-config.example.json to test-config.json and edit it."
    exit 1
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$InitPath = Join-Path $RepoRoot 'init.sh'
if (-not (Test-Path $InitPath)) {
    Write-Err "init.sh not found at $InitPath"
    exit 1
}

$configData = Get-Content $Config -Raw | ConvertFrom-Json
if (-not $configData.scenarios) {
    Write-Err "No scenarios found in config: $Config"
    exit 1
}

$scenarios = $configData.scenarios
if ($Scenario) {
    $scenarios = $scenarios | Where-Object { $_.name -eq $Scenario }
    if (-not $scenarios) {
        Write-Err "Scenario not found: $Scenario"
        exit 1
    }
}

$failures = 0

function Build-Image {
    param(
        [object]$Scenario
    )

    if (-not $Scenario.build) {
        return
    }

    if (-not $Scenario.image) {
        Write-Err "Build requested but image name missing for scenario: $($Scenario.name)"
        throw "Missing image name"
    }

    $context = $Scenario.build.context
    if (-not $context) {
        Write-Err "Build context missing for scenario: $($Scenario.name)"
        throw "Missing build context"
    }

    $contextPath = Resolve-Path (Join-Path $RepoRoot $context)
    $dockerfile = $Scenario.build.dockerfile
    if (-not $dockerfile) {
        $dockerfile = 'Dockerfile'
    }

    $dockerfilePath = Join-Path $contextPath $dockerfile
    if (-not (Test-Path $dockerfilePath)) {
        Write-Err "Dockerfile not found: $dockerfilePath"
        throw "Missing Dockerfile"
    }

    $buildArgs = @()
    if ($Scenario.build.args) {
        foreach ($key in $Scenario.build.args.PSObject.Properties.Name) {
            $value = $Scenario.build.args.$key
            $buildArgs += @('--build-arg', "$key=$value")
        }
    }

    $buildCmd = @('build', '-t', $Scenario.image, '-f', $dockerfilePath) + $buildArgs + @($contextPath)
    if ($DryRun) {
        Write-Info "DRY RUN: docker $($buildCmd -join ' ')"
        return
    }

    Write-Info "docker $($buildCmd -join ' ')"
    & docker @buildCmd
    if ($LASTEXITCODE -ne 0) {
        throw "Docker build failed for $($Scenario.name)"
    }
}

foreach ($scenario in $scenarios) {
    Write-Host ""
    Write-Info "Running scenario: $($scenario.name)"

    if (-not $scenario.image) {
        Write-Err "Missing image for scenario: $($scenario.name)"
        $failures++
        continue
    }

    if (-not $scenario.agent) {
        Write-Err "Missing agent for scenario: $($scenario.name)"
        $failures++
        continue
    }

    $requiredEnv = @()
    if ($scenario.requiredEnv) {
        $requiredEnv = $scenario.requiredEnv
    }

    foreach ($varName in $requiredEnv) {
        $value = [Environment]::GetEnvironmentVariable($varName)
        if (-not $value) {
            Write-Err "Missing required env var: $varName"
            $failures++
            continue 2
        }
    }

    try {
        Build-Image -Scenario $scenario
    } catch {
        Write-Err $_.Exception.Message
        $failures++
        continue
    }

    $agent = $scenario.agent.ToLower()
    $skillsPath = if ($agent -eq 'claude') { '~/.claude/skills' } else { '~/.codex/skills' }

    $cmdParts = @(
        'set -e',
        'cd /opt/agent-skills',
        'chmod +x ./init.sh',
        "./init.sh",
        "ls -la $skillsPath"
    )

    if ($scenario.setupCommands) {
        foreach ($setup in $scenario.setupCommands) {
            if ($setup) {
                $cmdParts += $setup
            }
        }
    }

    if ($scenario.agentCommand) {
        $cmdParts += $scenario.agentCommand
    }

    if ($scenario.prompts) {
        foreach ($prompt in $scenario.prompts) {
            if ($prompt.command) {
                $promptCmd = $prompt.command
                if ($prompt.env) {
                    $exports = @()
                    foreach ($envName in $prompt.env) {
                        $envValue = [Environment]::GetEnvironmentVariable($envName)
                        if (-not $envValue) {
                            Write-Err "Missing required env var for prompt '$($prompt.name)': $envName"
                            $failures++
                            continue 3
                        }
                        $escaped = $envValue.Replace("'", "'" + [char]34 + "'" + [char]34 + "'")
                        $exports += "export $envName='$escaped'"
                    }
                    if ($exports.Count -gt 0) {
                        $promptCmd = ($exports -join " && ") + " && " + $promptCmd
                    }
                }
                $cmdParts += $promptCmd
            }
        }
    }

    $cmd = $cmdParts -join " && "

    $dockerArgs = @(
        'run',
        '--rm',
        '-v', "${RepoRoot}:/opt/agent-skills",
        '-w', '/opt/agent-skills'
    )

    foreach ($varName in $requiredEnv) {
        $value = [Environment]::GetEnvironmentVariable($varName)
        $dockerArgs += @('-e', "$varName=$value")
    }

    $dockerArgs += @($scenario.image, 'bash', '-lc', $cmd)

    if ($DryRun) {
        Write-Info "DRY RUN: docker run --rm -v <repo>:/opt/agent-skills -w /opt/agent-skills -e <env vars> $($scenario.image) bash -lc <commands>"
        continue
    }

    Write-Info "docker run --rm -v <repo>:/opt/agent-skills -w /opt/agent-skills -e <env vars> $($scenario.image) bash -lc <commands>"
    & docker @dockerArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Scenario failed: $($scenario.name)"
        $failures++
    } else {
        Write-Ok "Scenario completed: $($scenario.name)"
    }
}

if ($failures -gt 0) {
    Write-Err "$failures scenario(s) failed"
    exit 1
}

Write-Ok "All scenarios completed"
