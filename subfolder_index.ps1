$immediateSubFolders = Get-ChildItem -Directory
$subFolderNames = @()

foreach ($subFolder in $immediateSubFolders) {
    $subFolderNames += Get-ChildItem -Path $subFolder.FullName -Directory | Select-Object -ExpandProperty Name
}

$subFolderNames = $subFolderNames | Sort-Object
$subFolderNames | Tee-Object -FilePath./index.txt
