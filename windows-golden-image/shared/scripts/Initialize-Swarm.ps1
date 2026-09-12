# Initialize-Swarm-WSL.ps1
# Run under the Windows account that owns the WSL distribution.
# Run after deployment, never while building the golden image.

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('manager', 'worker')]
    [string]$Role,

    [Parameter(Mandatory)]
    [ipaddress]$NodeIP,

    [ipaddress]$ManagerIP,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Distribution = 'Ubuntu-24.04'
)

$ErrorActionPreference = 'Stop'

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$LinuxArguments
    )

    & wsl.exe -d $Distribution -u root -- @LinuxArguments

    if ($LASTEXITCODE -ne 0) {
        throw "Command inside WSL failed with exit code $LASTEXITCODE."
    }
}

function Invoke-WslDocker {
    param(
        [Parameter(Mandatory)]
        [string[]]$DockerArguments
    )

    Invoke-WslCommand -LinuxArguments (@('docker') + $DockerArguments)
}

if ($NodeIP.AddressFamily -ne
    [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'NodeIP must be an IPv4 address assigned inside WSL.'
}

if ($Role -eq 'worker') {
    if (!$ManagerIP) {
        throw 'Worker requires -ManagerIP.'
    }

    if ($ManagerIP.AddressFamily -ne
        [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'ManagerIP must be an IPv4 address.'
    }
}

# Validate the address INSIDE Linux, not on Windows.
$addressJson = (
    Invoke-WslCommand -LinuxArguments @(
        'ip', '-j', '-4', 'address', 'show'
    ) | Out-String
)

$interfaces = $addressJson | ConvertFrom-Json

$localAddresses = @(
    foreach ($interface in $interfaces) {
        foreach ($address in $interface.addr_info) {
            $address.local
        }
    }
)

if ($NodeIP.IPAddressToString -notin $localAddresses) {
    throw (
        "NodeIP $NodeIP is not assigned inside '$Distribution'. " +
        "Available addresses: $($localAddresses -join ', ')"
    )
}

# Requires systemd enabled in this WSL distribution.
Invoke-WslCommand -LinuxArguments @(
    'systemctl', 'enable', '--now', 'docker'
)

$engineOS = (
    Invoke-WslDocker -DockerArguments @(
        'info', '--format', '{{.OSType}}'
    ) | Out-String
).Trim()

if ($engineOS -ne 'linux') {
    throw "Expected a Linux Docker engine inside WSL; got '$engineOS'."
}

$state = (
    Invoke-WslDocker -DockerArguments @(
        'info', '--format', '{{.Swarm.LocalNodeState}}'
    ) | Out-String
).Trim()

if ($state -ne 'inactive') {
    throw (
        "This WSL Docker engine already has Swarm state '$state'. " +
        'Inspect it before attempting another initialization or join.'
    )
}

if ($Role -eq 'manager') {
    Invoke-WslDocker -DockerArguments @(
        'swarm', 'init',
        '--advertise-addr', $NodeIP.IPAddressToString,
        '--data-path-addr', $NodeIP.IPAddressToString
    )

    Invoke-WslDocker -DockerArguments @(
        'node', 'update',
        '--label-add', 'runtime=wsl',
        'self'
    )

    Invoke-WslDocker -DockerArguments @('node', 'ls')
}
else {
    $secret = Read-Host 'Enter the manager-issued WORKER token' -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)

    try {
        $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)

        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'The worker token cannot be empty.'
        }

        Invoke-WslDocker -DockerArguments @(
            'swarm', 'join',
            '--token', $token,
            '--advertise-addr', $NodeIP.IPAddressToString,
            '--data-path-addr', $NodeIP.IPAddressToString,
            "$($ManagerIP.IPAddressToString):2377"
        )
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        $token = $null
        $secret.Dispose()
    }
}