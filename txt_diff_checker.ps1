# Get current directory path
$currentDir = $PSScriptRoot
$file1 = Join-Path $currentDir ""
$file2 = Join-Path $currentDir ""

# Check if files exist first
if (!(Test-Path $file1)) {
    Write-Warning "Cannot find file: $file1"
    exit
}
if (!(Test-Path $file2)) {
    Write-Warning "Cannot find file: $file2"
    exit
}

# Read files as bytes to check for BOM and encoding
$bytes1 = [System.IO.File]::ReadAllBytes($file1)
$bytes2 = [System.IO.File]::ReadAllBytes($file2)

# Check for BOM
Write-Host "File 1 BOM:" -ForegroundColor Yellow
if ($bytes1[0..2] -eq 239,187,191) { 
    Write-Host "Has UTF-8 BOM" 
} else { 
    Write-Host "No BOM" 
}

Write-Host "File 2 BOM:" -ForegroundColor Yellow
if ($bytes2[0..2] -eq 239,187,191) { 
    Write-Host "Has UTF-8 BOM" 
} else { 
    Write-Host "No BOM" 
}

# Compare content byte by byte
Write-Host "`nComparing content:" -ForegroundColor Yellow
if ($bytes1.Length -ne $bytes2.Length) {
    Write-Host "Files have different lengths: $($bytes1.Length) vs $($bytes2.Length)"
}

# Show where differences occur
for ($i = 0; $i -lt [Math]::Min($bytes1.Length, $bytes2.Length); $i++) {
    if ($bytes1[$i] -ne $bytes2[$i]) {
        Write-Host "Difference at position $i : $($bytes1[$i]) vs $($bytes2[$i])"
        Write-Host "As characters: '$([char]$bytes1[$i])' vs '$([char]$bytes2[$i])'"
        if ($i -lt 10) { continue } else { break }
    }
}
