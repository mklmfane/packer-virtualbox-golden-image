#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -eq 1 -or $os.BuildNumber -ne '20348') {
    throw 'This script targets Windows Server 2022 (build 20348).'
}
$result = Install-WindowsFeature -Name Containers
if (!$result.Success) { throw 'Windows Containers feature installation failed.' }
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform -All -NoRestart | Out-Null
Write-Host 'Windows Containers, WSL and Virtual Machine Platform enabled.'
Write-Host 'Restart Windows before installing Ubuntu. No automatic restart was requested.'
