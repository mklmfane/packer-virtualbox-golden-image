$ErrorActionPreference = 'Stop'
$service = Get-Service VBoxService -ErrorAction Stop
if ($service.Status -ne 'Running') { Start-Service VBoxService }
$service = Get-Service VBoxService
if ($service.Status -ne 'Running') { throw 'VBoxService is not running after reboot.' }
$control = 'C:\Program Files\Oracle\VirtualBox Guest Additions\VBoxControl.exe'
if (!(Test-Path $control)) { throw 'VBoxControl is missing.' }
& $control --version
if ($LASTEXITCODE -ne 0) { throw 'VBoxControl version check failed.' }
