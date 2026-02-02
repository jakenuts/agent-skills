# Shared .NET environment helpers for skills.
# Expects Write-Step/Write-Ok/Write-Warn/Write-Err in the caller (fallbacks used if missing).

function Invoke-DotnetLog {
    param(
        [string]$Level,
        [string]$Message
    )

    $fn = switch ($Level) {
        'Step' { 'Write-Step' }
        'Ok' { 'Write-Ok' }
        'Warn' { 'Write-Warn' }
        'Err' { 'Write-Err' }
        default { $null }
    }

    if ($fn -and (Get-Command $fn -ErrorAction SilentlyContinue)) {
        & $fn $Message
        return
    }

    switch ($Level) {
        'Step' { Write-Host "`n>> $Message" -ForegroundColor Cyan }
        'Ok' { Write-Host "   OK: $Message" -ForegroundColor Green }
        'Warn' { Write-Host "   WARN: $Message" -ForegroundColor Yellow }
        'Err' { Write-Host "   ERROR: $Message" -ForegroundColor Red }
        default { Write-Host $Message }
    }
}

function Set-DotnetEnv {
    param(
        [string]$InstallDir
    )

    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        if (-not [string]::IsNullOrWhiteSpace($env:DOTNET_INSTALL_DIR)) {
            $InstallDir = $env:DOTNET_INSTALL_DIR
        } else {
            $InstallDir = Join-Path $env:USERPROFILE '.dotnet'
        }
    }

    $env:DOTNET_INSTALL_DIR = $InstallDir
    $env:DOTNET_ROOT = $InstallDir
    $env:DOTNET_ROOT_X64 = $InstallDir
    $env:PATH = "$InstallDir;$InstallDir\tools;$env:PATH"
}

function Ensure-Dotnet {
    param(
        [string]$Channel
    )

    Set-DotnetEnv

    if ([string]::IsNullOrWhiteSpace($Channel)) {
        if (-not [string]::IsNullOrWhiteSpace($env:DOTNET_CHANNEL)) {
            $Channel = $env:DOTNET_CHANNEL
        } else {
            $Channel = '10.0'
        }
    }

    $version = $null
    try {
        $version = dotnet --version 2>$null
    } catch {
        $version = $null
    }

    if ($version) {
        $major = [int]($version.Split('.')[0])
        if ($major -ge 10) {
            Invoke-DotnetLog -Level 'Ok' -Message ".NET SDK $version detected"
            return
        }
        Invoke-DotnetLog -Level 'Warn' -Message ".NET SDK $version found, but 10.0+ is required"
    } else {
        Invoke-DotnetLog -Level 'Warn' -Message ".NET SDK not found"
    }

    Invoke-DotnetLog -Level 'Step' -Message "Installing .NET SDK $Channel"

    $installer = Join-Path $env:TEMP 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer
    & powershell -ExecutionPolicy Bypass -File $installer -Channel $Channel -InstallDir $env:DOTNET_INSTALL_DIR | Out-Null

    Invoke-DotnetLog -Level 'Ok' -Message ".NET SDK installed to $env:DOTNET_INSTALL_DIR"
    Invoke-DotnetLog -Level 'Warn' -Message "Add $env:DOTNET_INSTALL_DIR and $env:DOTNET_INSTALL_DIR\tools to your PATH for future shells"
}
