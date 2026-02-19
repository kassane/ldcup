# ldcup installer for Windows
# Usage:
#   irm https://github.com/kassane/ldcup/releases/latest/download/install.ps1 | iex
#   - or -
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Override install directory:
#   $env:LDCUP_INSTALL_DIR = "C:\tools\ldcup"; irm .../install.ps1 | iex

#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$BaseUrl     = "https://github.com/kassane/ldcup/releases/latest/download"
$InstallDir  = if ($env:LDCUP_INSTALL_DIR) { $env:LDCUP_INSTALL_DIR }
               else { Join-Path $env:LOCALAPPDATA "ldcup" }

# ---------------------------------------------------------------------------
# Available assets:
#   ldcup-windows-latest-amd64.zip      (x86_64)
#   ldcup-windows-11-arm-arm64.zip      (ARM64)
# ---------------------------------------------------------------------------
$Checksums = @{
    "ldcup-windows-latest-amd64.zip"   = "580cb2e600eda49e43f803914e70228a36ea775c5c1aa9e8625d7364312be67b"
    "ldcup-windows-11-arm-arm64.zip"   = "1608fb9c2e83d7609e8bc3cc323bb665cecddb51174e4fc1a9c0944b0f8da86b"
}

# ---------------------------------------------------------------------------
# Detect architecture
# ---------------------------------------------------------------------------
$Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
$FileName = switch ($Arch) {
    "X64"   { "ldcup-windows-latest-amd64.zip" }
    "Arm64" { "ldcup-windows-11-arm-arm64.zip"  }
    default {
        Write-Error "Error: architecture '$Arch' is not supported."
        exit 1
    }
}

$Url      = "$BaseUrl/$FileName"
$Expected = $Checksums[$FileName]

# ---------------------------------------------------------------------------
# Prepare install directory
# ---------------------------------------------------------------------------
if (-not (Test-Path $InstallDir)) {
    Write-Host "Creating installation directory at $InstallDir ..."
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

$ExistingBin = Join-Path $InstallDir "ldcup.exe"
if (Test-Path $ExistingBin) {
    Remove-Item $ExistingBin -Force
    Write-Host "Removed existing ldcup.exe."
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
$Archive = Join-Path $InstallDir $FileName
Write-Host "Downloading ldcup from $Url ..."
try {
    # Use TLS 1.2+ and a progress-friendly method
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $ProgressPreference = "SilentlyContinue"   # dramatically speeds up Invoke-WebRequest
    Invoke-WebRequest -Uri $Url -OutFile $Archive -UseBasicParsing
} catch {
    Write-Error "Error: download failed — $($_.Exception.Message)"
    exit 1
}
Write-Host "Download complete."

# ---------------------------------------------------------------------------
# Verify SHA256 checksum
# ---------------------------------------------------------------------------
Write-Host "Verifying checksum ..."
$Hash = (Get-FileHash -Path $Archive -Algorithm SHA256).Hash.ToLower()
if ($Hash -ne $Expected) {
    Write-Error "Error: checksum mismatch!`n  expected: $Expected`n  got:      $Hash"
    Remove-Item $Archive -Force
    exit 1
}
Write-Host "Checksum OK."

# ---------------------------------------------------------------------------
# Extract
# ---------------------------------------------------------------------------
Write-Host "Extracting $FileName ..."
try {
    Expand-Archive -Path $Archive -DestinationPath $InstallDir -Force
} catch {
    Write-Error "Error: extraction failed — $($_.Exception.Message)"
    Remove-Item $Archive -Force
    exit 1
}
Remove-Item $Archive -Force
Write-Host "Extraction complete."

# ---------------------------------------------------------------------------
# Verify binary
# ---------------------------------------------------------------------------
$LdcupBin = Join-Path $InstallDir "ldcup.exe"
if (-not (Test-Path $LdcupBin)) {
    Write-Error "Error: ldcup.exe not found at $LdcupBin after extraction."
    exit 1
}
Write-Host "ldcup.exe is ready at $LdcupBin"

# ---------------------------------------------------------------------------
# Add install directory to the user PATH (persistent)
# ---------------------------------------------------------------------------
Write-Host "Updating user PATH ..."
$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if (-not $UserPath.Split(";").Contains($InstallDir)) {
    [Environment]::SetEnvironmentVariable("PATH", "$UserPath;$InstallDir", "User")
    Write-Host "Added $InstallDir to user PATH."
} else {
    Write-Host "$InstallDir is already in user PATH."
}

# Also set in the current session so the bootstrap step below works immediately.
$env:PATH = "$env:PATH;$InstallDir"

# Set LDCUP_DIR for the user environment (persistent + current session).
[Environment]::SetEnvironmentVariable("LDCUP_DIR", $InstallDir, "User")
$env:LDCUP_DIR = $InstallDir
Write-Host "LDCUP_DIR set to $InstallDir"

# ---------------------------------------------------------------------------
# Bootstrap: install ldc2-latest
# ---------------------------------------------------------------------------
Write-Host "`nBootstrapping ldc2-latest ..."
& $LdcupBin install ldc2-latest --verbose
if ($LASTEXITCODE -ne 0) {
    Write-Error "Error: ldc2-latest installation failed (exit code $LASTEXITCODE)."
    exit 1
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host "`nInstallation complete."
Write-Host "Restart your terminal for PATH changes to take effect."