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

# Get the directory where the script is located
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Get the default user desktop path
$desktopPath = [Environment]::GetFolderPath("Desktop")

# --- Installed Software ---

# Create a unique filename for the Installed Software text file
$installedSoftwarePath = Join-Path -Path $desktopPath -ChildPath "Installed_Software.txt"
$installedSoftwareCounter = 1
while (Test-Path $installedSoftwarePath) {
    $installedSoftwarePath = Join-Path -Path $desktopPath -ChildPath "Installed_Software_$installedSoftwareCounter.txt"
    $installedSoftwareCounter++
}

# Get installed software
$software = Get-WmiObject -Class Win32_Product | Select-Object Name, Version, InstallDate, Vendor | Where-Object {$_.Name -ne $null}

# Format the software information
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

# Write the software information to the text file
$softwareOutput | Out-File -FilePath $installedSoftwarePath -Encoding UTF8

Write-Host "Installed Software information saved to: $installedSoftwarePath"

# --- OS Information ---

# Create a unique filename for the OS Information text file
$osInfoPath = Join-Path -Path $desktopPath -ChildPath "OS_Information.txt"
$osInfoCounter = 1
while (Test-Path $osInfoPath) {
    $osInfoPath = Join-Path -Path $desktopPath -ChildPath "OS_Information_$osInfoCounter.txt"
    $osInfoCounter++
}

# Get OS information using Get-ComputerInfo (default output)
$osInfo = Get-ComputerInfo

# Save OS information to the text file with UTF-8 encoding
$osInfo | Out-File -FilePath $osInfoPath -Encoding UTF8

Write-Host "OS information saved to: $osInfoPath"

# --- Autopilot Information ---

# Create a unique filename for the Autopilot Information text file
$autopilotInfoPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info.txt"
$autopilotInfoCounter = 1
while (Test-Path $autopilotInfoPath) {
    $autopilotInfoPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info_$autopilotInfoCounter.txt"
    $autopilotInfoCounter++
}

# Check if Get-WindowsAutoPilotInfo is installed
if (!(Get-Command Get-WindowsAutoPilotInfo -ErrorAction SilentlyContinue)) {
    # Install the script
    Install-Script -Name Get-WindowsAutoPilotInfo -Force
}

# Get Autopilot information (make sure the script is loaded). Get-WindowsAutoPilotInfo # Dot-source the script to load it into the current scope

# Get Autopilot information (default output)
$autopilotInfo = Get-WindowsAutoPilotInfo

# Save Autopilot information to the text file
$autopilotInfo | Out-File -FilePath $autopilotInfoPath

Write-Host "Autopilot information saved to: $autopilotInfoPath"

#Read-Host "This line is used to hold the script for debugging purposes"
