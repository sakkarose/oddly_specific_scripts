# Requires elevated privileges (Run as Administrator)
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "Run this script as Administrator."
    exit 1
}

Write-Host "Microsoft Edge Removal Script"

# Function to uninstall Edge packages (with retries)
function Uninstall-EdgePackage {
    param(
        [string]$PackageName
    )
    for ($i = 0; $i -lt 3; $i++) { # Retry up to 3 times
        Get-AppxPackage -Name $PackageName | Remove-AppxPackage
        if (-Not (Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)) {
            return # Uninstall successful
        }
        Write-Warning "Failed to uninstall '$PackageName'. Retrying..."
        Start-Sleep -Seconds 5 # Wait before retrying
    }
    Write-Error "Failed to uninstall '$PackageName' after multiple attempts."
}

# Uninstall Edge packages
Write-Host "Uninstalling Edge packages..."
Uninstall-EdgePackage "Microsoft.MicrosoftEdge"
Uninstall-EdgePackage "Microsoft.MicrosoftEdgeDev"  # If you have Edge Dev installed
Uninstall-EdgePackage "Microsoft.MicrosoftEdgeWebView2Runtime" 

# Remove Edge files and folders
Write-Host "Removing Edge files and folders..."
$edgePaths = @(
    "C:\Program Files (x86)\Microsoft\Edge"
    "$env:LOCALAPPDATA\Microsoft\Edge"
    "$env:PROGRAMDATA\Microsoft\Edge"
    "$env:PROGRAMDATA\Microsoft\EdgeUpdate"
)
$edgePaths | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove Edge registry keys
Write-Host "Removing Edge registry keys..."
$edgeRegistryKeys = @(
    "HKLM:\SOFTWARE\Microsoft\EdgeUpdate"
    "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    "HKCU:\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppContainer\Storage\microsoft.microsoftedge_8wekyb3d8bbwe"
)
$edgeRegistryKeys | ForEach-Object {
    if (Test-Path $_) {
        Remove-Item $_ -Recurse -ErrorAction SilentlyContinue
    }
}

# Clean up scheduled tasks
Write-Host "Removing Edge scheduled tasks..."
Get-ScheduledTask | Where-Object { $_.TaskPath -like "Microsoft\Edge*" } | Unregister-ScheduledTask -Confirm:$false

# Additional cleanup (optional)
Write-Host "Performing additional cleanup..."
Remove-Item "C:\Program Files (x86)\Microsoft\EdgeWebView" -Recurse -Force -ErrorAction SilentlyContinue
Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.pdf -Name "ProgId" -ErrorAction SilentlyContinue

Write-Host "Edge Removal Complete! You may need to restart your computer."
