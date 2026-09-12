$ErrorActionPreference = 'Stop'
Start-Transcript C:\WindowsLab\seal.log -Force
Unregister-ScheduledTask -TaskName WindowsLabSeal -Confirm:$false -ErrorAction SilentlyContinue
# Runs as SYSTEM after all provisioning has completed.
if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
    $encrypted = @(Get-BitLockerVolume | Where-Object { $_.VolumeStatus -ne 'FullyDecrypted' })
    if ($encrypted.Count -gt 0) { throw 'Decrypt all BitLocker volumes before sealing this generic template.' }
}
if (Get-Service docker -ErrorAction SilentlyContinue) {
    Stop-Service docker -Force
    # This is a fresh golden build with no workloads. Avoid cloning Docker IDs/HNS state.
    Remove-Item C:\ProgramData\docker -Recurse -Force
    New-Item -ItemType Directory -Force C:\ProgramData\docker\config | Out-Null
    '{"hosts":["npipe://"],"exec-opts":["isolation=process"]}' | Set-Content C:\ProgramData\docker\config\daemon.json -Encoding Ascii
}
if (Test-Path C:\WindowsLab\payloads) { Remove-Item C:\WindowsLab\payloads -Recurse -Force }
foreach ($path in @('C:\Windows\Panther\unattend.xml','C:\Windows\Panther\Unattend.xml','C:\Windows\Panther\Unattend\Unattend.xml','C:\Windows\System32\Sysprep\unattend.xml')) {
    Remove-Item $path -Force -ErrorAction SilentlyContinue
}
Disable-LocalUser -Name packer
# OOBE establishes credentials for each deployed VM. No Swarm join token is baked in.
Remove-NetFirewallRule -Name PackerWinRM -ErrorAction SilentlyContinue
Remove-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -ErrorAction SilentlyContinue
# Keep current WinRM session alive until Sysprep starts; listener cleanup happens first.
Get-ChildItem WSMan:\localhost\Listener | Remove-Item -Recurse -Force
if (Test-Path C:\WindowsLab\build-cert.txt) {
    $thumb = (Get-Content C:\WindowsLab\build-cert.txt).Trim()
    Remove-Item "Cert:\LocalMachine\My\$thumb" -ErrorAction SilentlyContinue
    Remove-Item C:\WindowsLab\build-cert.txt
}
$p = Start-Process "$env:WINDIR\System32\Sysprep\Sysprep.exe" -ArgumentList '/generalize','/oobe','/shutdown','/quiet' -PassThru -Wait
if ($p.ExitCode -ne 0) { throw "Sysprep failed ($($p.ExitCode)); inspect C:\Windows\System32\Sysprep\Panther." }
