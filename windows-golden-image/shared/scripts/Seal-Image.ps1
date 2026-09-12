# Detach final sealing from the WinRM session before removing its listener.
$ErrorActionPreference = 'Stop'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\WindowsLab\Finalize-Image.ps1'
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15)
$principal = New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName WindowsLabSeal -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
Write-Host 'Sealing scheduled. Packer will wait for Sysprep to shut down the VM.'
