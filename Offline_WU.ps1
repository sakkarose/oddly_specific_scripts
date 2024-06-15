# Check for elevation
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Output "This script requires elevation. Restarting as Administrator..."
    Start-Process PowerShell.exe -Verb RunAs -ArgumentList "-NoExit","-File",$MyInvocation.MyCommand.Path
    exit
}

# Get the directory where the script is located
$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Find all .msu (Microsoft Update Standalone) files in the script directory
$updateFiles = Get-ChildItem $scriptDirectory -Filter "*.msu"

Write-Output "Starting Windows Update installation at $(Get-Date)"

# Install each update file
foreach ($updateFile in $updateFiles) {
    Write-Output "Installing update: $($updateFile.Name)"

    # Run the update installer silently with no restart
    Start-Process -FilePath "wusa.exe" "$($updateFile.FullName) /quiet /norestart" -Wait
}

Write-Output "Update script completed at $(Get-Date)"
Write-Host "Press Enter to close this window..."
Read-Host 
