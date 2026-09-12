# Runs as SYSTEM during Windows specialize. Build-only HTTPS WinRM, not RDP.
$ErrorActionPreference = 'Stop'
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
Enable-PSRemoting -Force -SkipNetworkProfileCheck
$cert = New-SelfSignedCertificate -DnsName 'WIN-TEMPLATE' -CertStoreLocation Cert:\LocalMachine\My
New-Item WSMan:\localhost\Listener -Transport HTTPS -Address '*' -CertificateThumbPrint $cert.Thumbprint -Force | Out-Null
Set-Item WSMan:\localhost\Service\AllowUnencrypted $false
Set-Item WSMan:\localhost\Service\Auth\Basic $false
Set-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Type DWord -Value 1
Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -contains 'Transport=HTTP' } | Remove-Item -Recurse -Force
Get-NetFirewallRule -Name 'WINRM-HTTP-In-TCP*' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
New-NetFirewallRule -Name PackerWinRM -DisplayName 'Packer build HTTPS' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5986 -RemoteAddress 10.0.2.2 -Profile Any | Out-Null
New-Item -ItemType Directory -Force C:\WindowsLab | Out-Null
$cert.Thumbprint | Set-Content C:\WindowsLab\build-cert.txt
