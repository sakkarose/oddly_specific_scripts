# Stored hash URL
$hashFileURL = "https://file.mizu.reisen/share/mdm_survey_hash.txt"
$scriptURL = "https://file.mizu.reisen/share/MDM_survey.ps1"

# Download the hash
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

# Get script content and detect BOM
if ($MyInvocation.MyCommand.Path) {
    # For local file
    $originalContent = [System.IO.File]::ReadAllBytes($MyInvocation.MyCommand.Path)
    $scriptContent = [System.Text.Encoding]::UTF8.GetString($originalContent)
    
    # Detect if file has BOM
    $hasBOM = ($originalContent.Length -ge 3) -and 
              ($originalContent[0] -eq 239) -and 
              ($originalContent[1] -eq 187) -and 
              ($originalContent[2] -eq 191)
} else {
    try {
        $webResponse = Invoke-WebRequest -Uri $scriptURL -UseBasicParsing
        $scriptContent = [System.Text.Encoding]::UTF8.GetString($webResponse.Content)
        $hasBOM = $false
    } catch {
        Write-Warning "Failed to download original script: $_"
        exit
    }
}

# Calculate hash from normalized content
$normalizedContent = $scriptContent.Replace("`r`n", "`n")
$bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedContent)
$currentHash = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new($bytes)) -Algorithm SHA256).Hash

# Save local copy with original encoding
[System.IO.File]::WriteAllText(
    $tempScriptPath, 
    $scriptContent,
    [System.Text.UTF8Encoding]::new($hasBOM)
)

try {
    if ($expectedHash) {
        if ($currentHash -ne $expectedHash) {
            Write-Warning "Script hash mismatch! The script might have been modified."
            exit
        }
        Write-Host "Script integrity verified."
    } else {
        Write-Warning "Skipping hash verification due to download error."
    }

    # Running as administrator
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Warning "This script requires administrator privileges. Please run PowerShell as Administrator."
        exit
    }

    # --- Installed Software ---
    $installedSoftwarePath = Join-Path -Path $desktopPath -ChildPath "Installed_Software.docx"
    $installedSoftwareCounter = 1
    while (Test-Path $installedSoftwarePath) {
        $installedSoftwarePath = Join-Path -Path $desktopPath -ChildPath "Installed_Software_$installedSoftwareCounter.docx"
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
    $osInfoPath = Join-Path -Path $desktopPath -ChildPath "OS_Information.docx"
    $osInfoCounter = 1
    while (Test-Path $osInfoPath) {
        $osInfoPath = Join-Path -Path $desktopPath -ChildPath "OS_Information_$osInfoCounter.docx"
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
            
            $autopilotInfoPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info.docx"
            $autopilotInfoCounter = 1
            while (Test-Path $autopilotInfoPath) {
                $autopilotInfoPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info_$autopilotInfoCounter.docx"
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

    Write-Host "Script execution completed. Files have been saved to your desktop."
    $scriptSuccess = $true
}
catch {
    Write-Warning "An error occurred: $_"
    $scriptSuccess = $false
    throw
}
finally {
    Start-Sleep -Seconds 1
    if (Test-Path $tempScriptPath) {
        Remove-Item -Path $tempScriptPath -Force -ErrorAction SilentlyContinue
    }
}

if ($scriptSuccess) {
    Read-Host "Press Enter to exit"
    explorer.exe $desktopPath
}
