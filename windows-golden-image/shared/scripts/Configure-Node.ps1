# Run in an elevated PowerShell console AFTER importing and finishing Windows OOBE.
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9-]{0,14}$')][string]$ComputerName,
    [Parameter(Mandatory)][string]$InterfaceAlias,
    [Parameter(Mandatory)][ipaddress]$NodeIP,
    [int]$PrefixLength = 24
)
$ErrorActionPreference='Stop'
if ($NodeIP.AddressFamily -ne 'InterNetwork') { throw 'Use an IPv4 node address.' }
$nic=Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
$existing=@(Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)
if ($existing | Where-Object { $_.IPAddress -ne $NodeIP.IPAddressToString -and $_.IPAddress -notlike '169.254.*' }) {
    throw 'Selected NIC already has another IPv4 address; inspect it before changing networking.'
}
if (!(Get-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $NodeIP.IPAddressToString -ErrorAction SilentlyContinue)) {
    New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $NodeIP.IPAddressToString -PrefixLength $PrefixLength | Out-Null
}
# No gateway or DNS on host-only NIC: NAT remains the default route.
Set-DnsClient -InterfaceIndex $nic.ifIndex -RegisterThisConnectionsAddress $false
if ($env:COMPUTERNAME -ne $ComputerName) { Rename-Computer -NewName $ComputerName -Force }
Write-Host 'Restart this VM, then run Initialize-Swarm.ps1 if it is a Server container host.'
