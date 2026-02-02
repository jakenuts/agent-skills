# Shared .NET runtime helpers for skills.
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

function Should-PersistDotnetPath {
    $value = $env:DOTNET_PERSIST_PATH
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $true
    }

    switch ($value.ToLowerInvariant()) {
        '0' { return $false }
        'false' { return $false }
        'no' { return $false }
        default { return $true }
    }
}

function Set-DotnetRuntimeEnv {
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

    $pathEntries = $env:PATH -split ';'
    if ($pathEntries -notcontains $InstallDir) {
        $env:PATH = "$InstallDir;$env:PATH"
    }
}

function Update-DotnetRuntimeProfile {
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

        $marker = '# Added by Codex dotnet runtime'
        $content = Get-Content -Path $profileTarget -ErrorAction SilentlyContinue
        if ($content -and ($content -match [regex]::Escape($marker))) {
            return
        }
        if ($content -and ($content -match [regex]::Escape($InstallDir))) {
            return
        }

        Add-Content -Path $profileTarget -Value ''
        Add-Content -Path $profileTarget -Value $marker
        Add-Content -Path $profileTarget -Value "`$env:DOTNET_ROOT = '$InstallDir'"
        Add-Content -Path $profileTarget -Value "`$env:DOTNET_ROOT_X64 = '$InstallDir'"
        Add-Content -Path $profileTarget -Value "`$env:PATH = '$InstallDir;' + `$env:PATH"
    } catch {
        Invoke-DotnetLog -Level 'Warn' -Message "Could not update PowerShell profile: $($_.Exception.Message)"
    }
}

function Ensure-DotnetRuntime {
    param(
        [string]$Channel,
        [int]$RequiredMajor
    )

    Set-DotnetRuntimeEnv
    if (Should-PersistDotnetPath) {
        Update-DotnetRuntimeProfile -InstallDir $env:DOTNET_INSTALL_DIR
    }

    if ([string]::IsNullOrWhiteSpace($Channel)) {
        if (-not [string]::IsNullOrWhiteSpace($env:DOTNET_CHANNEL)) {
            $Channel = $env:DOTNET_CHANNEL
        } else {
            $Channel = '10.0'
        }
    }

    if (-not $RequiredMajor) {
        if (-not [string]::IsNullOrWhiteSpace($env:DOTNET_REQUIRED_MAJOR)) {
            $RequiredMajor = [int]$env:DOTNET_REQUIRED_MAJOR
        } else {
            $RequiredMajor = [int]($Channel.Split('.')[0])
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
        if ($major -ge $RequiredMajor) {
            Invoke-DotnetLog -Level 'Ok' -Message ".NET SDK $version detected"
            return
        }
        Invoke-DotnetLog -Level 'Warn' -Message ".NET SDK $version found, but $RequiredMajor.0+ is required"
    } else {
        Invoke-DotnetLog -Level 'Warn' -Message ".NET SDK not found"
    }

    Invoke-DotnetLog -Level 'Step' -Message "Installing .NET SDK $Channel"

    $installer = Join-Path $env:TEMP 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer
    & powershell -ExecutionPolicy Bypass -File $installer -Channel $Channel -InstallDir $env:DOTNET_INSTALL_DIR | Out-Null

    Invoke-DotnetLog -Level 'Ok' -Message ".NET SDK installed to $env:DOTNET_INSTALL_DIR"
    Invoke-DotnetLog -Level 'Warn' -Message "Add $env:DOTNET_INSTALL_DIR to your PATH for future shells"
}
