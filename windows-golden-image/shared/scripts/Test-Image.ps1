param([ValidateSet('server2022','windows11')][string]$Target)
. C:\WindowsLab\Common.ps1
if ($Target -eq 'server2022') {
    Invoke-Docker version
    $os = Invoke-Docker info --format '{{.OSType}}'
    if ($os -ne 'windows') { throw 'Expected Windows container engine.' }
    $swarm = Invoke-Docker info --format '{{.Swarm.LocalNodeState}}'
    if ($swarm -ne 'inactive') { throw 'Do not seal an image with a Swarm identity.' }
} else {
    if (!(Test-Path 'C:\Program Files\Docker\Docker\Docker Desktop.exe')) { throw 'Desktop installation missing.' }
    Write-Host 'Desktop installed; Windows-container runtime needs an interactive first-launch test after deployment.'
}
Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber | ConvertTo-Json | Set-Content C:\WindowsLab\image-build-info.json
