param([ValidateSet('server2022')][string]$Target)
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
if ($Target -eq 'server2022') {
    if ($os.ProductType -eq 1 -or $os.BuildNumber -ne '20348') { throw 'Expected Windows Server 2022 (build 20348).' }
    $result = Install-WindowsFeature -Name Containers
    if (!$result.Success) { throw 'Containers feature installation failed.' }
} else {
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 22000) { throw 'Expected Windows 11 Enterprise/Pro.' }
    Enable-WindowsOptionalFeature -Online -FeatureName Containers -All -NoRestart | Out-Null
}
# Packer owns the restart, preventing an unexpected communicator disconnect.
