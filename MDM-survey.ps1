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

# Get the default user desktop path
$desktopPath = [Environment]::GetFolderPath("Desktop")

# Create a unique filename (prevents overwriting)
$counter = 1
$excelPath = Join-Path -Path $desktopPath -ChildPath "MDM_survey.xlsx"
while (Test-Path $excelPath) {
    $excelPath = Join-Path -Path $desktopPath -ChildPath "MDM_survey_$counter.xlsx"
    $counter++
}

# Create a unique filename for the CSV file (prevents overwriting)
$csvPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info.csv"
$csvCounter = 1
while (Test-Path $csvPath) {
    $csvPath = Join-Path -Path $desktopPath -ChildPath "Autopilot_Info_$csvCounter.csv"
    $csvCounter++
}

# Create an Excel object
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false

# Create a new workbook
$workbook = $excel.Workbooks.Add()

# Rename the first sheet
$worksheet = $workbook.Worksheets.Item(1)
$worksheet.Name = "Installed Software"

# Add headers
$worksheet.Cells(1, 1) = "Software Name"
$worksheet.Cells(1, 2) = "Version"
$worksheet.Cells(1, 3) = "Install Date"
$worksheet.Cells(1, 4) = "Publisher"

# Get installed software
$software = Get-WmiObject -Class Win32_Product | Select-Object Name, Version, InstallDate, Vendor | Where-Object {$_.Name -ne $null}
#Get-ComputerInfo

$row = 2

foreach ($app in $software) {
    try {
        $worksheet.Cells($row, 1) = $app.Name
        $worksheet.Cells($row, 2) = $app.Version

        if ($app.InstallDate) {
            $installDate = [datetime]::ParseExact($app.InstallDate.Substring(0,8), "yyyyMMdd", $null).ToString("dd/MM/yyyy")
            $worksheet.Cells($row, 3) = $installDate
        } else {
            $worksheet.Cells($row, 3) = "" # Handle cases where InstallDate is null
        }

        $worksheet.Cells($row, 4) = $app.Vendor
        $row++
    }
    catch {
        Write-Warning "Error processing software: $($app.Name) - $($_.Exception.Message)"
    }
}

$osWorksheet = $workbook.Sheets.Add()
$osWorksheet.Name = "OS Information"

# Get OS information using Get-ComputerInfo (default output)
$osInfo = Get-ComputerInfo
$tempFile = New-TemporaryFile
$osInfo | Out-String | Set-Content -Path $tempFile.FullName -Encoding UTF8
Get-Content -Path $tempFile.FullName | Clip

# Paste the clipboard content into the sheet
$osWorksheet.Range("A1").PasteSpecial()

# Remove the temporary file
Remove-Item $tempFile.FullName

# Auto-fit columns for the OS sheet
$osWorksheet.Columns.AutoFit()

# Check if Get-WindowsAutoPilotInfo is installed
if (!(Get-Command Get-WindowsAutoPilotInfo -ErrorAction SilentlyContinue)) {
    Install-Script -Name Get-WindowsAutoPilotInfo -Force
}

$autopilotInfo = Get-WindowsAutoPilotInfo
$autopilotInfo | Export-Csv -Path $csvPath -NoTypeInformation

Write-Host "Autopilot information saved to: $csvPath"

try {
    $workbook.SaveAs($excelPath, 51)
    $workbook.Close()
    Write-Host "Software list saved to: $excelPath"
}
catch {
    Write-Error "Error saving Excel file: $($_.Exception.Message)"
}

$excel.Quit()

# Release COM objects & garbage collection
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($worksheet) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($osWorksheet) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) | Out-Null
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
