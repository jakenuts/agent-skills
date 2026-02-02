# Shared .NET global tool helpers for skills.
# Expects Write-Step/Write-Ok/Write-Warn/Write-Err in the caller (fallbacks used if missing).

$runtimeHelper = $env:DOTNET_RUNTIME_HELPER
if ([string]::IsNullOrWhiteSpace($runtimeHelper)) {
    $runtimeHelper = Join-Path $PSScriptRoot 'dotnet-runtime.ps1'
}

if (-not (Test-Path $runtimeHelper)) {
    Write-Host "   ERROR: Shared dotnet runtime helper not found: $runtimeHelper" -ForegroundColor Red
    throw "Shared dotnet runtime helper not found: $runtimeHelper"
}

. $runtimeHelper

function Set-DotnetToolsEnv {
    param(
        [string]$InstallDir
    )

    Set-DotnetRuntimeEnv -InstallDir $InstallDir

    $toolsDir = Join-Path $env:DOTNET_INSTALL_DIR 'tools'
    $pathEntries = $env:PATH -split ';'
    if ($pathEntries -notcontains $toolsDir) {
        $env:PATH = "$toolsDir;$env:PATH"
    }
}

function Update-DotnetToolsProfile {
    param(
        [string]$InstallDir
    )

    try {
        if ([string]::IsNullOrWhiteSpace($InstallDir)) {
            $InstallDir = $env:DOTNET_INSTALL_DIR
        }

        if ([string]::IsNullOrWhiteSpace($InstallDir)) {
            $InstallDir = Join-Path $env:USERPROFILE '.dotnet'
        }

        $profileTarget = $PROFILE
        if ($PROFILE.PSObject.Properties.Name -contains 'CurrentUserAllHosts') {
            $profileTarget = $PROFILE.CurrentUserAllHosts
        }

        $profileDir = Split-Path -Parent $profileTarget
        if (-not (Test-Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        if (-not (Test-Path $profileTarget)) {
            New-Item -ItemType File -Path $profileTarget -Force | Out-Null
        }

        $marker = '# Added by Codex dotnet tools'
        $toolsDir = Join-Path $InstallDir 'tools'
        $content = Get-Content -Path $profileTarget -ErrorAction SilentlyContinue
        if ($content -and ($content -match [regex]::Escape($marker))) {
            return
        }
        if ($content -and ($content -match [regex]::Escape($toolsDir))) {
            return
        }

        Add-Content -Path $profileTarget -Value ''
        Add-Content -Path $profileTarget -Value $marker
        Add-Content -Path $profileTarget -Value "`$env:PATH = '$toolsDir;' + `$env:PATH"
    } catch {
        Invoke-DotnetLog -Level 'Warn' -Message "Could not update PowerShell profile: $($_.Exception.Message)"
    }
}

function Ensure-DotnetToolsEnv {
    param(
        [string]$InstallDir
    )

    Set-DotnetToolsEnv -InstallDir $InstallDir
    Update-DotnetToolsProfile -InstallDir $env:DOTNET_INSTALL_DIR
}

function Install-DotnetTool {
    param(
        [string]$PackageId,
        [string]$Version,
        [string]$ToolsDir,
        [string]$CommandName,
        [string]$Channel,
        [int]$RequiredMajor
    )

    if ([string]::IsNullOrWhiteSpace($PackageId)) {
        throw 'Missing .NET tool package id'
    }

    if (-not [string]::IsNullOrWhiteSpace($ToolsDir)) {
        if (-not (Test-Path $ToolsDir)) {
            throw "Tool package directory not found: $ToolsDir"
        }
    }

    $installed = $null
    try {
        $installed = dotnet tool list --global 2>$null | Select-String $PackageId
    } catch {}

    if ($installed) {
        Invoke-DotnetLog -Level 'Ok' -Message "Tool already installed: $PackageId"
        return
    }

    $label = $PackageId
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $label = "$PackageId v$Version"
    }
    Invoke-DotnetLog -Level 'Step' -Message "Installing $label"

    $args = @('--global')
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $args += @('--version', $Version)
    }
    if (-not [string]::IsNullOrWhiteSpace($ToolsDir)) {
        $args += @('--add-source', $ToolsDir)
    }

    & dotnet tool install $PackageId @args | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($CommandName)) {
        if (Get-Command $CommandName -ErrorAction SilentlyContinue) {
            Invoke-DotnetLog -Level 'Ok' -Message "Tool installed: $CommandName"
        } else {
            Invoke-DotnetLog -Level 'Warn' -Message "Tool installed but '$CommandName' is not on PATH. Restart your shell and try again."
        }
    }
}
