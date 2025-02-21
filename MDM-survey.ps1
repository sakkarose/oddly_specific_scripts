# Running as administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $response = Read-Host "This script requires administrator privileges. Do you want to restart as administrator? (Y/N)"

    if ($response -eq "Y") {
        Start-Process powershell -Verb RunAs -ArgumentList "-File", $MyInvocation.MyCommand.Path
        exit
    } else {
        Write-Warning "Script requires administrator privileges to run. Exiting."
        exit
    }
}

# Stored hash
$hashFileURL = "https://file.mizu.reisen/share/mdm_survey_hash.txt"

# Download the hash
$expectedHash = try {
    Invoke-WebRequest -Uri $hashFileURL -UseBasicParsing | Select-Object -ExpandProperty Content
} catch {
    Write-Warning "Failed to download the expected hash from '$hashFileURL'. Skipping hash verification."
    $null
}

# Calculate the hash
$currentHash = Get-FileHash -Path $MyInvocation.MyCommand.Path -Algorithm SHA256 | Select-Object -ExpandProperty Hash

# Compare the hashes
if ($expectedHash) {
    if ($currentHash -eq $expectedHash) {
        Write-Host "Script integrity verified."

        # Get the directory where the script is located
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

        # Get the default user desktop path
        $desktopPath = [Environment]::GetFolderPath("Desktop")

        # --- Installed Software ---

        # Create a unique filename
        $installedSoftwarePath = Join-Path -Path $desktopPath -ChildPath "Installed_Software.txt"
        $installedSoftwareCounter = 1
        while (Test-Path $installedSoftwarePath) {
            $installedSoftwarePath = Join-Path -Path $desktopPath -ChildPath "Installed_Software_$installedSoftwareCounter.txt"
            $installedSoftwareCounter++
        }

        # Get
        $software = Get-WmiObject -Class Win32_Product | Select-Object Name, Version, InstallDate, Vendor | Where-Object {$_.Name -ne $null}

        # Format
        $softwareOutput = ""
        foreach ($app in $software) {
            try {
                $installDate = if ($app.InstallDate) {
                    [datetime]::ParseExact($app.InstallDate.Substring(0,8), "yyyyMMdd", $null).ToString("dd/MM/yyyy")
                } else {
                    "" # Handle cases where InstallDate is null
                }

                $softwareOutput += @"
Software Name: $($app.Name)
Version: $($app.Version)
Install Date: $installDate
Publisher: $($app.Vendor)

"@
            }
            catch {
                Write-Warning "Error processing software: $($app.Name) - $($_.Exception.Message)"
            }
        }

        # Write
        $softwareOutput | Out-File -FilePath $installedSoftwarePath -Encoding UTF8

        Write-Host "Installed Software information saved to: $installedSoftwarePath"

        # --- OS Information ---

        # Create a unique filename
        $osInfoPath = Join-Path -Path $desktopPath -ChildPath "OS_Information.txt"
        $osInfoCounter = 1
        while (Test-Path $osInfoPath) {
            $osInfoPath = Join-Path -Path $desktopPath -ChildPath "OS_Information_$osInfoCounter.txt"
            $osInfoCounter++
        }

        # Get
        $osInfo = Get-ComputerInfo

        # Save OS with UTF-8 encoding
        $osInfo | Out-File -FilePath $osInfoPath -Encoding UTF8

        Write-Host "OS information saved to: $osInfoPath"

        # --- Autopilot Information ---

        # Check for internet connection
        if (Test-Connection 8.8.8.8 -Quiet) {
            # Check if Get-WindowsAutoPilotInfo is installed
            if (!(Get-Command Get-WindowsAutoPilotInfo -ErrorAction SilentlyContinue)) {
                # Install the script
                Install-Script -Name Get-WindowsAutoPilotInfo -Force
            }

            # Check if NuGet is installed
            if (-not (Get-PackageProvider NuGet -ErrorAction SilentlyContinue)) {
                # Install NuGet silently
                Install-PackageProvider -Name NuGet -Force -Verbose
            }
        } else {
            Write-Warning "No internet connection detected. Unable to install the Autopilot script and NuGet."
        }

        # Create a unique filename
        $autopilotInfoPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info.txt"
        $autopilotInfoCounter = 1
        while (Test-Path $autopilotInfoPath) {
            $autopilotInfoPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info_$autopilotInfoCounter.txt"
            $autopilotInfoCounter++
        }

        # Make sure the script is loaded
        . Get-WindowsAutoPilotInfo

        # Get Autopilot information
        $autopilotInfo = Get-WindowsAutoPilotInfo

        # Save
        $autopilotInfo | Out-File -FilePath $autopilotInfoPath

        Write-Host "Autopilot information saved to: $autopilotInfoPath"
    } else {
        Read-Host "Script hash mismatch! The script might have been modified. Press Enter to exit."
        exit
    }
} else {
    Write-Warning "Skipping hash verification due to download error."
}

Read-Host "This line is to hold the script for debugging. Press Enter to finish."
