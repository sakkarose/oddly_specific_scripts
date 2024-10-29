$immediateSubFolders = Get-ChildItem -Directory
$subFolderNames = @()

foreach ($subFolder in $immediateSubFolders) {
    $subFolderNames += Get-ChildItem -Path $subFolder.FullName -Directory | Select-Object -ExpandProperty Name
}

$subFolderNames | Tee-Object -FilePath./index.txt
