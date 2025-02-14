# Get network adapter information
function Get-NetAdapterInfo {
  $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
  for ($i = 0; $i -lt $adapters.Count; $i++) {
    Write-Host "[$($i + 1)]. $($adapters[$i].Name) - $($adapters[$i].InterfaceDescription) - $($adapters[$i].MacAddress) - $($adapters[$i].Status)" # Corrected line
  }
}

function Set-MacAddress {
  param(
    [string]$AdapterName,
    [string]$NewMacAddress
  )

  try {
    # Get the adapter object
    $adapter = Get-NetAdapter -Name $AdapterName

    if ($adapter.Status -ne "Up") {
        Write-Warning "Adapter '$AdapterName' is not currently up. Please ensure it is enabled."
        return
    }

    # Disable the adapter
    try {
        Disable-NetAdapter -Name $AdapterName -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Error "Failed to disable adapter: $_"
        return
    }

    # Set the new MAC address
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
    $adapterGuid = $adapter.InterfaceGuid
    
    # Ensure the adapter is disabled and the registry isn't locked
    Start-Sleep -Seconds 2

    try {
        $netCfgInstanceId = (Get-ItemProperty -Path $regPath | Get-ChildItem | Where-Object {$_.PSChildName -match $adapterGuid} | Get-ItemProperty).NetCfgInstanceId
        Set-ItemProperty -Path "$regPath\$netCfgInstanceId" -Name "NetworkAddress" -Value $NewMacAddress -Force -ErrorAction Stop
    } catch {
        Write-Error "Failed to set MAC address in registry: $_"
        # Re-enable in case of error
        Enable-NetAdapter -Name $AdapterName -Confirm:$false
        return
    }

    # Re-enable the adapter (with error handling)
    try {
        Enable-NetAdapter -Name $AdapterName -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Error "Failed to re-enable adapter: $_"
        return
    }

    Write-Host "MAC address for '$AdapterName' changed to '$NewMacAddress'."

    # Verify the change
    $adapter = Get-NetAdapter -Name $AdapterName
    if ($adapter.MacAddress -ne $NewMacAddress) {
        Write-Warning "MAC address change not reflected immediately. Check Device Manager or try disabling/re-enabling the adapter manually."
    }

  }
  catch {
    Write-Error "Failed to change MAC address: $_"
  }
}

# Display network adapter information
Write-Host "Available Network Adapters:"
$adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} # Store the adapters in a variable
Get-NetAdapterInfo

# Prompt
$adapterIndex = Read-Host "Enter the number of the adapter to modify (or 'q' to quit)"

if ($adapterIndex -eq "q") {
    exit
}

# Validate
if ($adapterIndex -match "^\d+$" -and $adapterIndex -ge 1 -and $adapterIndex -le $adapters.Count) {
    $selectedIndex = [int]$adapterIndex - 1 # Adjust for 0-based indexing
    $selectedAdapter = $adapters[$selectedIndex]  # Correct way to access the adapter
} else {
    Write-Error "Invalid adapter selection. Please enter a number between 1 and $($adapters.Count)."
    exit
}

if ($selectedAdapter) {
  Write-Host "Selected Adapter: $($selectedAdapter.Name) - $($selectedAdapter.InterfaceDescription)"

  # New MAC address or random
  $newMac = Read-Host "Enter new MAC address (or 'r' for random, 'q' to quit)"

  if ($newMac -eq "q") {
      exit
  }

  if ($newMac -eq "r") {
    # Generate a random MAC address
    $newMac = "02" + (Get-Random -Minimum 0x00 -Maximum 0xffffffff).ToString("X8")
    $newMac = ($newMac -replace '..', '$0:') -replace '.$', ''
  }

  # Validate
  if ($newMac -match "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$") {
      Set-MacAddress -AdapterName $selectedAdapter.Name -NewMacAddress $newMac
  } else {
      Write-Error "Invalid MAC address format. Please use the format XX:XX:XX:XX:XX:XX"
  }

} else {
  Write-Host "Invalid adapter selection."
}
