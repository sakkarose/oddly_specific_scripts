# Stored hash URL
$hashFileURL = "https://file.mizu.reisen/share/mdm_survey_hash.txt"
$scriptURL = "https://raw.githubusercontent.com/sakkarose/oddly_specific_scripts/refs/heads/main/MDM-survey.ps1"

# Download the hash and original script
$expectedHash = try {
    (Invoke-WebRequest -Uri $hashFileURL -UseBasicParsing).Content.Trim()
} catch {
    Write-Warning "Failed to download the expected hash from '$hashFileURL'. Skipping hash verification."
    $null
}

# Save script content to desktop for verification
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$desktopPath = [Environment]::GetFolderPath("Desktop")
$tempScriptPath = Join-Path $desktopPath "MDM_survey_temp_$timestamp.ps1"

# Get script content
if ($MyInvocation.MyCommand.Path) {
    # Local file execution - read and normalize line endings
    $scriptContent = [System.IO.File]::ReadAllText($MyInvocation.MyCommand.Path)
} else {
    # Remote execution
    try {
        $response = Invoke-WebRequest -Uri $scriptURL -UseBasicParsing
        $scriptContent = [System.Text.Encoding]::UTF8.GetString($response.Content)
    } catch {
        Write-Warning "Failed to download original script for verification: $_"
        exit
    }
}

# Normalize line endings
$scriptContent = $scriptContent.Replace("`r`n", "`n").Replace("`r", "`n").Replace("`n", "`r`n")
$utf8NoBOM = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($tempScriptPath, $scriptContent, $utf8NoBOM)

# Calculate hash from temp file
try {
    $currentHash = (Get-FileHash -Path $tempScriptPath -Algorithm SHA256).Hash
    
    if ($expectedHash) {
        if ($currentHash -eq $expectedHash) {
            Write-Host "Script integrity verified."
            Write-Host "Script temp saved to: $tempScriptPath"
            
            # Running as administrator
            if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                Write-Warning "This script requires administrator privileges. Please run PowerShell as Administrator."
                exit
            }

            # --- Installed Software ---
            $installedSoftwarePath = Join-Path -Path $desktopPath -ChildPath "Installed_Software.txt"
            $installedSoftwareCounter = 1
            while (Test-Path $installedSoftwarePath) {
                $installedSoftwarePath = Join-Path -Path $desktopPath -ChildPath "Installed_Software_$installedSoftwareCounter.txt"
                $installedSoftwareCounter++
            }

            # Get software info
            $software = Get-WmiObject -Class Win32_Product | Select-Object Name, Version, InstallDate, Vendor | Where-Object {$_.Name -ne $null}

            # Format software info
            $softwareOutput = ""
            foreach ($app in $software) {
                try {
                    $installDate = if ($app.InstallDate) {
                        [datetime]::ParseExact($app.InstallDate.Substring(0,8), "yyyyMMdd", $null).ToString("dd/MM/yyyy")
                    } else {
                        ""
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

            # --- OS Info ---

            # Create a unique filename
            $osInfoPath = Join-Path -Path $desktopPath -ChildPath "OS_Information.txt"
            $osInfoCounter = 1
            while (Test-Path $osInfoPath) {
                $osInfoPath = Join-Path -Path $desktopPath -ChildPath "OS_Information_$osInfoCounter.txt"
                $osInfoCounter++
            }

            # Get
            $osInfo = Get-ComputerInfo

            # Save OS info
            $osInfo | Out-File -FilePath $osInfoPath -Encoding UTF8

            Write-Host "OS information saved to: $osInfoPath"

            # --- Autopilot Info ---
            if (Test-Connection 8.8.8.8 -Quiet -Count 1) {
                try {
                    if (!(Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser > $null
                    }
                    
                    if (!(Get-InstalledScript -Name Get-WindowsAutoPilotInfo -ErrorAction SilentlyContinue)) {
                        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted > $null
                        Install-Script -Name Get-WindowsAutoPilotInfo -Force -Scope CurrentUser > $null
                    }
                    
                    $autopilotInfoPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info.csv"
                    $autopilotInfoCounter = 1
                    while (Test-Path $autopilotInfoPath) {
                        $autopilotInfoPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info_$autopilotInfoCounter.csv"
                        $autopilotInfoCounter++
                    }
                    
                    # Load the function silently
                    . Get-WindowsAutoPilotInfo > $null
                    
                    # Capture and export
                    $autopilotData = Get-WindowsAutoPilotInfo 2>$null
                    $autopilotData | Export-Csv -Path $autopilotInfoPath -NoTypeInformation
                    
                    Write-Host "Autopilot information saved to: $autopilotInfoPath"
                }
                catch {
                    Write-Warning "Error installing required modules: $_"
                }
            } else {
                Write-Warning "No internet connection detected. Skipping Autopilot information."
            }

            Read-Host "Script execution completed. Files have been saved to your desktop. Press Enter to exit"
            explorer.exe $desktopPath
        } else {
            Write-Warning "Script hash mismatch! The script might have been modified."
            exit
        }
    } else {
        Write-Warning "Skipping hash verification due to download error."
    }
}
catch {
    Write-Warning "An error occurred: $_"
    throw
}
finally {
    # Doublecheck on cleaning
    Start-Sleep -Seconds 1
    if (Test-Path $tempScriptPath) {
        Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
    }
}
