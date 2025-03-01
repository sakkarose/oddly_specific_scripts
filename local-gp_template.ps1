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
$AlwaysAutoRebootAtScheduledTime = 1
$AutoInstallMinorUpdates = 1

$CredentialGuardEnabled = 1

$RestrictSingleSession = 0
$IdleSessionLimit = 0 # 0 = Never

try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "legalnoticeText" -Value $MessageText -Type String

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "MaxIdleTime" -Value $IdleSessionLimit -Type DWord

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fDisableCdm" -Value $DriveRedirectionDisabled -Type DWord

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredUI" -Name "DisablePasswordReveal" -Value $PasswordRevealButtonDisabled -Type DWord

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableAutoDoh" -Value $DoHSetting -Type DWord

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -Name "DeferFeatureUpdatesPeriodInDays" -Value $FeatureUpdateDeferralDays -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value $NoAutoUpdate -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value $AUOptions -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AutomaticMaintenanceEnabled" -Value $AutomaticMaintenanceEnabled -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallDay" -Value $ScheduledInstallDay -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallTime" -Value $ScheduledInstallTime -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AlwaysAutoRebootAtScheduledTime" -Value $AlwaysAutoRebootAtScheduledTime -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AutoInstallMinorUpdates" -Value $AutoInstallMinorUpdates -Type DWord

    # Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" -Name "RequirePlatformSecurityFeatures" -Value 1 -Type DWord
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard" -Name "LsaCfgFlags" -Value $CredentialGuardEnabled -Type DWord

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services" -Name "fSingleSessionPerUser" -Value $RestrictSingleSession -Type DWord

    Write-Host "Local Group Policy settings updated successfully."

    gpupdate /force

}
catch {
    Write-Error "An error occurred: $($_.Exception.Message)"
}