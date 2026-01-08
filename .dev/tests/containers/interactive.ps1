<#
.SYNOPSIS
    Interactive Container Launcher
.DESCRIPTION
    Builds and runs a container with an agent CLI, deploys skills,
    and drops you into an interactive shell.
.PARAMETER Agent
    Which agent to use: 'claude' or 'codex'. Default: claude
.EXAMPLE
    .\interactive.ps1 claude
    Launch with Claude Code
.EXAMPLE
    .\interactive.ps1 codex
    Launch with Codex CLI
#>

param(
    [ValidateSet('claude', 'codex')]
    [string]$Agent = 'claude'
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir '..\..\..') | Select-Object -ExpandProperty Path

switch ($Agent) {
    'claude' {
        $ImageName = 'agent-skills-claude-code:local'
        $Dockerfile = Join-Path $ScriptDir 'images\claude-code\Dockerfile'
        $BuildContext = Join-Path $ScriptDir 'images\claude-code'
        $AgentCmd = 'claude'
        $SkillsDir = '/root/.claude/skills'
        $EnvVar = 'ANTHROPIC_API_KEY'
    }
    'codex' {
        $ImageName = 'agent-skills-codex-cli:local'
        $Dockerfile = Join-Path $ScriptDir 'images\codex-cli\Dockerfile'
        $BuildContext = Join-Path $ScriptDir 'images\codex-cli'
        $AgentCmd = 'codex'
        $SkillsDir = '/root/.codex/skills'
        $EnvVar = 'OPENAI_API_KEY'
    }
}

Write-Host "=== Interactive Agent Container ===" -ForegroundColor Cyan
Write-Host "Agent: $AgentCmd"
Write-Host "Image: $ImageName"
Write-Host ""

# Check for API key
$ApiKeyValue = [Environment]::GetEnvironmentVariable($EnvVar)
if ([string]::IsNullOrWhiteSpace($ApiKeyValue)) {
    Write-Host "WARNING: $EnvVar is not set" -ForegroundColor Yellow
    Write-Host "The agent will not be able to make API calls without it."
    Write-Host ""
    $response = Read-Host "Continue anyway? (y/N)"
    if ($response -notmatch '^[Yy]$') {
        Write-Host "Set $EnvVar and try again."
        exit 1
    }
}

# Build the image
Write-Host "Building container image..." -ForegroundColor Cyan
docker build -t $ImageName `
    -f $Dockerfile `
    --build-arg CLAUDE_CODE_VERSION=latest `
    --build-arg CODEX_VERSION=latest `
    --build-arg DOTNET_CHANNEL=10.0 `
    $BuildContext

Write-Host ""
Write-Host "Starting interactive container..." -ForegroundColor Cyan
Write-Host "Skills will be deployed on startup."
Write-Host ""
Write-Host "Once inside, try:" -ForegroundColor Green
Write-Host "  $AgentCmd --version"
Write-Host "  ls $SkillsDir"
Write-Host "  $AgentCmd"
Write-Host ""
Write-Host "Type 'exit' to leave the container."
Write-Host "==========================================="
Write-Host ""

# Build docker args
$DockerArgs = @(
    'run'
    '--rm'
    '-it'
    '-v', "${RepoRoot}:/opt/agent-skills"
    '-w', '/opt/agent-skills'
)

# Add API key if set
if (-not [string]::IsNullOrWhiteSpace($ApiKeyValue)) {
    $DockerArgs += @('-e', "$EnvVar=$ApiKeyValue")
}

# Add other common env vars if set
$swToken = $env:SOLARWINDS_API_TOKEN
$wpSite = $env:WP_SITE_URL
$wpUser = $env:WP_USERNAME
$wpPass = $env:WP_APP_PASSWORD

if ($swToken) { $DockerArgs += @('-e', "SOLARWINDS_API_TOKEN=$swToken") }
if ($wpSite) { $DockerArgs += @('-e', "WP_SITE_URL=$wpSite") }
if ($wpUser) { $DockerArgs += @('-e', "WP_USERNAME=$wpUser") }
if ($wpPass) { $DockerArgs += @('-e', "WP_APP_PASSWORD=$wpPass") }

$DockerArgs += $ImageName

# Entry command
$EntryCmd = "echo 'Deploying skills...' && ./init.sh --force && echo '' && echo 'Ready! Skills deployed to $SkillsDir' && echo '' && exec bash -l"
$DockerArgs += @('bash', '-lc', $EntryCmd)

& docker @DockerArgs
