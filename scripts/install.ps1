$ldcupBaseUrl = "https://github.com/kassane/ldcup/releases/latest/download"
$ldcupInstallDir = "$HOME\.dlang"
$architecture = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "x86" }
$ldcupFileName = "ldcup-windows-$architecture.zip"
$ldcupExeFileName = "ldcup.exe"
$ldcupZipPath = "$ldcupInstallDir\$ldcupFileName"
$ldcupExePath = "$ldcupInstallDir\$ldcupExeFileName"
$ldcupRenamedExePath = "$ldcupInstallDir\ldcup.exe"
$ldcupUrl = "$ldcupBaseUrl/$ldcupFileName"

# Check if the architecture is x86 (32-bit)
if ($architecture -eq "x86") {
    Write-Output "Error: 32-bit (x86) version is not available yet."
    Write-Output "Build your own 32-bit version of ldcup from source."
    exit 1
}

# Create the installation directory if it doesn't exist
if (-not (Test-Path -Path $ldcupInstallDir)) {
    Write-Output "Creating installation directory at $ldcupInstallDir..."
    New-Item -Path $ldcupInstallDir -ItemType Directory | Out-Null
}

# Download the latest release
Write-Output "Downloading ldcup from $ldcupUrl..."
try {
    Invoke-WebRequest -Uri $ldcupUrl -OutFile $ldcupZipPath
    Write-Output "Download complete."
} catch {
    Write-Output "Error: Failed to download ldcup. Please check your internet connection and URL."
    exit 1
}

# Unzip the downloaded file
Write-Output "Extracting ldcup..."
try {
    Expand-Archive -Path $ldcupZipPath -DestinationPath $ldcupInstallDir -Force
    Write-Output "Extraction complete."
} catch {
    Write-Output "Error: Failed to extract $ldcupFileName. Please check the file and try again."
    Remove-Item -Path $ldcupZipPath
    exit 1
}

# Remove the downloaded zip file
Remove-Item -Path $ldcupZipPath

# Check if the existing ldcup.exe exists and remove it
if (Test-Path -Path $ldcupRenamedExePath) {
    Remove-Item -Path $ldcupRenamedExePath -Force
    Write-Output "Removed existing ldcup.exe."
}

# Rename the new executable
if (Test-Path -Path $ldcupExePath) {
    Rename-Item -Path $ldcupExePath -NewName "ldcup.exe"
    Write-Output "Renamed $ldcupExeFileName to ldcup.exe"

    try {
        # Set the user environment variable
        Write-Output "Setting LDCUP_DIR environment variable..."
        [System.Environment]::SetEnvironmentVariable("LDCUP_DIR", $ldcupInstallDir, [System.EnvironmentVariableTarget]::User)
        Write-Output "LDCUP_DIR has been set to $ldcupInstallDir for the current user."

        # Add the ldcup directory to the user PATH
        $currentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::User)
        if ($currentPath -notlike "*$ldcupInstallDir*") {
            $newPath = "$currentPath;$ldcupInstallDir"
            [System.Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::User)
            Write-Output "Added $ldcupInstallDir to PATH for the current user."
        } else {
            Write-Output "$ldcupInstallDir is already in the user PATH."
        }
    } catch {
        Write-Output "Error: Unable to set environment variable or update PATH. Please run the script as an administrator."
    }
} else {
    Write-Output "Error: ldcup executable not found after extraction. Please check the downloaded files."
    exit 1
}

Write-Output "Installation complete. Please restart your terminal or computer to apply changes."