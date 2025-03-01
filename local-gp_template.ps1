$MessageText = "Idle timeout: 30m.`nHave a good day."
$IdleSessionLimit = 1800000 # 1800000 milliseconds (30 minutes)
$DriveRedirectionDisabled = 0
$PasswordRevealButtonDisabled = 0
$DoHSetting = 2 # 2 = Allow DoH
$FeatureUpdateDeferralDays = 365
$NoAutoUpdate = 0
$AUOptions = 4
$AutomaticMaintenanceEnabled = 1
$ScheduledInstallDay = 7 # Saturday
$ScheduledInstallTime = 3 # 3 AM

$CredentialGuardEnabled = 1
$RestrictSingleSession = 0

try {
    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "legalnoticeText" -Value $MessageText -Type String

    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "MaxIdleTime" -Value $IdleSessionLimit -Type DWord

    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "fDisableCdm" -Value $DriveRedirectionDisabled -Type DWord

    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\CredUI" -ValueName "DisablePasswordReveal" -Value $PasswordRevealButtonDisabled -Type DWord

    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -ValueName "EnableAutoDoh" -Value $DoHSetting -Type DWord

    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ValueName "DeferFeatureUpdatesPeriodInDays" -Value $FeatureUpdateDeferralDays -Type DWord

    # Set Automatic Updates settings
    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "NoAutoUpdate" -Value $NoAutoUpdate -Type DWord
    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "AUOptions" -Value $AUOptions -Type DWord
    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "AutomaticMaintenanceEnabled" -Value $AutomaticMaintenanceEnabled -Type DWord
    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "ScheduledInstallDay" -Value $ScheduledInstallDay -Type DWord
    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValueName "ScheduledInstallTime" -Value $ScheduledInstallTime -Type DWord

    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" -ValueName "RequirePlatformSecurityFeatures" -Value $CredentialGuardEnabled -Type DWord

    Set-GPRegistryValue -Name "Local Computer" -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -ValueName "fSingleSessionPerUser" -Value $RestrictSingleSession -Type DWord

    Write-Host "Local Group Policy settings updated successfully."

    gpupdate /force

}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
}