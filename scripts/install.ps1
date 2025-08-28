$ldcupBaseUrl = "https://github.com/kassane/ldcup/releases/latest/download"
$ldcupInstallDir = Join-Path $HOME ".dlang"
$ldcupRenamedExePath = Join-Path $ldcupInstallDir "ldcup.exe"
$processorArch = $env:PROCESSOR_ARCHITECTURE.ToLower()

switch ($processorArch) {
    "amd64" {
        $fileArch = "amd64"
        $ldcupFileName = "ldcup-windows-latest-$fileArch.zip"
    }
    "arm64" {
        $fileArch = "arm64"
        $ldcupFileName = "ldcup-windows-11-arm-$fileArch.zip"
        
        # Check if running on Windows 11 or later for ARM64
        $os = Get-CimInstance Win32_OperatingSystem
        if ($os.BuildNumber -lt 22000) {
            Write-Output "Error: ARM64 support requires Windows 11 or later."
            exit 1
        }
    }
    "x86" {
        Write-Output "Error: 32-bit (x86) version is not available yet."
        Write-Output "Build your own 32-bit version of ldcup from source."
        exit 1
    }
    default {
        Write-Output "Error: Unsupported architecture: $processorArch"
        exit 1
    }
}

$ldcupZipPath = Join-Path $ldcupInstallDir $ldcupFileName
$ldcupExePath = Join-Path $ldcupInstallDir "ldcup.exe"
$ldcupUrl = "$ldcupBaseUrl/$ldcupFileName"

# Create the installation directory if it doesn't exist
if (-not (Test-Path -Path $ldcupInstallDir -PathType Container)) {
    Write-Output "Creating installation directory at $ldcupInstallDir..."
    New-Item -Path $ldcupInstallDir -ItemType Directory | Out-Null
}

# Remove existing ldcup.exe if it exists
if (Test-Path -Path $ldcupRenamedExePath) {
    Remove-Item -Path $ldcupRenamedExePath -Force
    Write-Output "Removed existing ldcup.exe."
}

# Download the latest release
Write-Output "Downloading ldcup from $ldcupUrl..."
try {
    Invoke-WebRequest -Uri $ldcupUrl -OutFile $ldcupZipPath -ErrorAction Stop
    Write-Output "Download complete."
} catch {
    Write-Output "Error: Failed to download ldcup. Please check your internet connection and ensure the URL is correct."
    Write-Output "Details: $($_.Exception.Message)"
    exit 1
}

# Unzip the downloaded file
Write-Output "Extracting ldcup..."
try {
    Expand-Archive -Path $ldcupZipPath -DestinationPath $ldcupInstallDir -Force -ErrorAction Stop
    Write-Output "Extraction complete."
} catch {
    Write-Output "Error: Failed to extract $ldcupFileName. Please check the file integrity."
    Write-Output "Details: $($_.Exception.Message)"
    Remove-Item -Path $ldcupZipPath -ErrorAction SilentlyContinue
    exit 1
}

# Remove the downloaded zip file
Remove-Item -Path $ldcupZipPath -ErrorAction SilentlyContinue

# Check if the executable exists after extraction
if (Test-Path -Path $ldcupExePath) {
    Write-Output "ldcup.exe is ready."

    # Set the user environment variable
    Write-Output "Setting LDCUP_DIR environment variable..."
    [System.Environment]::SetEnvironmentVariable("LDCUP_DIR", $ldcupInstallDir, [System.EnvironmentVariableTarget]::User)
    Write-Output "LDCUP_DIR has been set to $ldcupInstallDir for the current user."

    # Add the ldcup directory to the user PATH if not already present
    $currentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
    if ($currentPath -notlike "*$ldcupInstallDir*") {
        $newPath = "$currentPath;$ldcupInstallDir".Trim(';')
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::User)
        Write-Output "Added $ldcupInstallDir to PATH for the current user."
    } else {
        Write-Output "$ldcupInstallDir is already in the user PATH."
    }
} else {
    Write-Output "Error: ldcup executable not found after extraction. Please verify the downloaded zip contents."
    exit 1
}

Write-Output "Installation complete. Please restart your terminal or log out and back in to apply changes."