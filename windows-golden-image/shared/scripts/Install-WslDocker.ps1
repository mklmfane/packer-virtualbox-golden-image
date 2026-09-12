#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
Windows Server 2022 post-deployment installer (no Microsoft Store).
Run as the FINAL Windows user who will own the WSL distribution, not SYSTEM.
Stages: Features -> reboot -> Runtime -> Ubuntu -> Docker -> Swarm.
Docker inside WSL runs Linux containers. The Windows Containers feature is separate.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Features','Runtime','Ubuntu','Docker','Swarm','Verify')]
    [string]$Stage,
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Distribution = 'Ubuntu-24.04',
    [System.Net.IPAddress]$AdvertiseAddress
)
$ErrorActionPreference = 'Stop'
$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -eq 1 -or $os.BuildNumber -ne '20348') {
    throw 'This script targets Windows Server 2022 (build 20348).'
}
if ([Security.Principal.WindowsIdentity]::GetCurrent().IsSystem) {
    throw 'Use the final Windows administrator account, not SYSTEM: WSL distributions belong to individual users.'
}
$installationType = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').InstallationType
# Direct MSI/rootfs installation works without relying on the Microsoft Store.
if (![Environment]::Is64BitProcess) { throw 'Run 64-bit PowerShell.' }
function Invoke-WslChecked {
    param([string[]]$Arguments)
    & wsl.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed with exit code $LASTEXITCODE. Review the output above."
    }
}
function Assert-Distribution {
    $names = (& wsl.exe --list --quiet 2>$null | Out-String).Replace([string][char]0,'')
    if ($LASTEXITCODE -ne 0) { throw 'Could not list WSL distributions. Complete the Ubuntu stage first.' }
    if ($Distribution -notin @($names -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        throw "Distribution '$Distribution' is not registered for this Windows account. Run the Ubuntu stage first."
    }
}
if ($Stage -eq 'Features') {
    $result = Install-WindowsFeature -Name Containers
    if (!$result.Success) { throw 'Windows Containers installation failed.' }
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux,VirtualMachinePlatform -All -NoRestart | Out-Null
    Set-TimeZone -Id 'GTB Standard Time'
    Write-Host 'Features enabled. Run Restart-Computer, then run this script with -Stage Runtime.'
    return
}
function Get-Download {
    param([string]$Uri, [string]$Destination)
    $partial = $Destination + '.partial'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $partial
        Move-Item -LiteralPath $partial -Destination $Destination -Force
    } finally {
        Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
    }
}
if ($Stage -eq 'Runtime') {
    # Install WSL directly from Microsoft's signed MSI, without Microsoft Store.
    $cache = Join-Path $env:LOCALAPPDATA 'WindowsLab\Downloads'
    New-Item -ItemType Directory -Force $cache | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/WSL/releases/latest' -Headers @{ 'User-Agent' = 'WindowsLab-ServerCore' }
    $assets = @($release.assets | Where-Object { $_.name -match '^wsl\..*\.x64\.msi$' })
    if ($assets.Count -ne 1) { throw 'Could not select a unique stable x64 WSL MSI from Microsoft releases.' }
    $msi = Join-Path $cache $assets[0].name
    Write-Host "Downloading WSL $($release.tag_name): $($assets[0].name)"
    Get-Download -Uri $assets[0].browser_download_url -Destination $msi
    $signature = Get-AuthenticodeSignature -FilePath $msi
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw 'WSL MSI must have a valid Microsoft Authenticode signature.'
    }
    $log = Join-Path $cache 'wsl-install.log'
    $process = Start-Process -FilePath msiexec.exe -ArgumentList @('/i', ('"' + $msi + '"'), '/qn', '/norestart', '/L*v', ('"' + $log + '"')) -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010,1641)) { throw "WSL MSI failed ($($process.ExitCode)); inspect $log" }
    if ($process.ExitCode -in @(3010,1641)) {
        Write-Host 'WSL MSI requests a reboot.'
        exit 3010
    }
    Invoke-WslChecked -Arguments @('--version')
    Write-Host 'WSL runtime installed. Continue with -Stage Ubuntu.'
    return
}
if ($Stage -eq 'Ubuntu') {
    Invoke-WslChecked -Arguments @('--version')
    $names = (& wsl.exe --list --quiet 2>$null | Out-String).Replace([string][char]0,'')
    if ($LASTEXITCODE -ne 0) { throw 'Could not list distributions. Complete Runtime and reboot if requested.' }
    if ($Distribution -in @($names -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        Write-Host "Reusing existing distribution '$Distribution'; no data was replaced."
        Invoke-WslChecked -Arguments @('--set-version',$Distribution,'2')
        Invoke-WslChecked -Arguments @('--list','--verbose')
        return
    }
    # Canonical's Ubuntu WSL root filesystem: no Store/AppX/OOBE launcher needed.
    $base = 'https://cloud-images.ubuntu.com/wsl/noble/current'
    $filename = 'ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz'
    $cache = Join-Path $env:LOCALAPPDATA 'WindowsLab\Downloads'
    $install = Join-Path $env:LOCALAPPDATA ('WindowsLab\WSL\' + $Distribution)
    if (Test-Path -LiteralPath $install) { throw "Import directory already exists: $install. Inspect it rather than overwriting it." }
    New-Item -ItemType Directory -Force $cache | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $sums = Join-Path $cache 'Ubuntu-SHA256SUMS'
    $archive = Join-Path $cache $filename
    Get-Download -Uri ($base + '/SHA256SUMS') -Destination $sums
    $pattern = '^([0-9a-fA-F]{64})\s+\*?' + [regex]::Escape($filename) + '$'
    $hashes = @(Get-Content -LiteralPath $sums | ForEach-Object {
        if ($_.Trim() -match $pattern) { $Matches[1].ToLowerInvariant() }
    })
    if ($hashes.Count -ne 1) { throw 'Expected one checksum for the Ubuntu rootfs in Canonical SHA256SUMS.' }
    Write-Host 'Downloading Ubuntu 24.04 WSL root filesystem from Canonical...'
    Get-Download -Uri ($base + '/' + $filename) -Destination $archive
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hashes[0]) {
        throw 'Ubuntu rootfs checksum mismatch. The current image may have changed; rerun the Ubuntu stage.'
    }
    New-Item -ItemType Directory -Path $install -Force | Out-Null
    Invoke-WslChecked -Arguments @('--import',$Distribution,$install,$archive,'--version','2')
    Invoke-WslChecked -Arguments @('--list','--verbose')
    Invoke-WslChecked -Arguments @('-d',$Distribution,'-u','root','--','cat','/etc/os-release')
    Write-Host 'Ubuntu imported without Microsoft Store. It initially uses root; the Docker stages explicitly use root.'
    Write-Host 'Continue with -Stage Docker.'
    return
}

Assert-Distribution
# A current WSL release with systemd support is required (>= 0.67.6).
Invoke-WslChecked -Arguments @('--version')
if ($Stage -eq 'Verify') {
    Invoke-WslChecked -Arguments @('-d',$Distribution,'-u','root','--','docker','version')
    Invoke-WslChecked -Arguments @('-d',$Distribution,'-u','root','--','docker','compose','version')
    Invoke-WslChecked -Arguments @('-d',$Distribution,'-u','root','--','docker','info')
    return
}
$LinuxInstaller = @'
#!/usr/bin/env bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
phase=${1:-install}
case "$phase" in systemd|install|swarm) ;; *) echo 'Usage: sudo bash docker-wsl.sh systemd|install|swarm [advertise-IP]' >&2; exit 1;; esac
. /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || { echo 'Expected Ubuntu 24.04 inside WSL.' >&2; exit 1; }
grep -qi microsoft /proc/sys/kernel/osrelease || { echo 'Expected WSL.' >&2; exit 1; }
if [[ $phase == systemd ]]; then
    command -v python3 >/dev/null || { apt-get update; apt-get install -y python3; }
    python3 - <<'PY'
import configparser, pathlib, shutil, tempfile, os
path = pathlib.Path('/etc/wsl.conf')
config = configparser.ConfigParser(interpolation=None, strict=True)
if path.exists():
    config.read(path)
    if not path.with_suffix('.conf.before-docker').exists():
        shutil.copy2(path, path.with_suffix('.conf.before-docker'))
if not config.has_section('boot'): config.add_section('boot')
config.set('boot','systemd','true')
with tempfile.NamedTemporaryFile(mode='w', dir='/etc', delete=False) as f:
    config.write(f)
    temp = f.name
os.chmod(temp,0o644)
os.replace(temp,path)
PY
    echo 'systemd configured. Exit Ubuntu and terminate ONLY this distro from Windows, then reopen it.'
    exit 0
fi
[[ $(ps -p 1 -o comm=) == systemd ]] || { echo 'systemd is not PID 1. Run the systemd phase and restart this WSL distribution.' >&2; exit 1; }
if [[ $phase == install ]]; then
    # Fail clearly instead of removing another runtime or an existing Docker installation.
    for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            echo "Conflicting package found: $package. Review its workloads before replacing it." >&2
            exit 1
        fi
    done
    if command -v docker >/dev/null && ! dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q 'install ok installed'; then
        echo 'A Docker client/runtime from another installation exists. Inspect it before proceeding.' >&2
        exit 1
    fi
    # Existing Docker sources may use another keyring or package policy. Preserve them.
    if grep -Rqs 'download.docker.com' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null && [[ ! -f /etc/apt/sources.list.d/windowslab-docker.sources ]]; then
        echo 'An existing Docker APT source was found. Inspect it before adding this one.' >&2
        exit 1
    fi
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl tzdata
    install -m 0755 -d /etc/apt/keyrings
    temp_key=$(mktemp)
    trap 'rm -f "$temp_key"' EXIT
    curl --fail --silent --show-error --location https://download.docker.com/linux/ubuntu/gpg --output "$temp_key"
    install -m 0644 "$temp_key" /etc/apt/keyrings/windowslab-docker.asc
    cat > /etc/apt/sources.list.d/windowslab-docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/windowslab-docker.asc
EOF
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    timedatectl set-timezone Europe/Bucharest
    systemctl enable --now containerd docker
    docker version
    docker compose version
    [[ $(docker info --format '{{.OSType}}') == linux ]] || { echo 'Expected Linux engine.' >&2; exit 1; }
    dpkg-query -W docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /var/log/windowslab-docker-versions.txt
    echo 'Linux Docker Engine and Compose installed. Swarm commands are built into Engine.'
    echo 'Use sudo docker; membership in the docker group is not required.'
    exit 0
fi
systemctl start docker
state=$(docker info --format '{{.Swarm.LocalNodeState}}')
[[ $state == inactive ]] || { echo "Existing Swarm state: $state. No reset or reinitialization performed."; exit 0; }
node_ip=${2:-$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1);exit}}')}
python3 - "$node_ip" <<'PY'
import ipaddress,sys
ipaddress.IPv4Address(sys.argv[1])
PY
ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$node_ip" || { echo 'Advertise IP is not assigned inside WSL.' >&2; exit 1; }
docker swarm init --advertise-addr "$node_ip" --data-path-addr "$node_ip"
docker node ls
echo 'Single-node lab Swarm initialized. WSL NAT/IP lifecycle needs separate design for remote workers.'
'@
# Run a real LF-terminated file; avoid PowerShell pipeline CRLF corrupting Bash input.
$tempPath = Join-Path ([IO.Path]::GetTempPath()) ('windowslab-docker-' + [guid]::NewGuid().ToString('N') + '.sh')
try {
    [IO.File]::WriteAllText($tempPath, $LinuxInstaller.Replace("`r`n","`n") + "`n", (New-Object Text.UTF8Encoding($false)))
    $linuxPath = (& wsl.exe -d $Distribution -u root -- wslpath -u $tempPath | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or !$linuxPath.StartsWith('/')) {
        throw 'Could not map the temporary script into WSL. Windows drive mounting must be available.'
    }
    if ($Stage -eq 'Docker') {
        # The distro conversion fails rather than silently attempting Docker on WSL 1.
        Invoke-WslChecked -Arguments @('--set-version',$Distribution,'2')
        $pid1 = (& wsl.exe -d $Distribution -u root -- ps -p 1 -o comm= | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect PID 1 inside WSL.' }
        if ($pid1 -ne 'systemd') {
            Invoke-WslChecked -Arguments @('-d',$Distribution,'-u','root','--','bash',$linuxPath,'systemd')
            Write-Host "Restarting only '$Distribution' to activate systemd; other work in that distro will stop."
            Invoke-WslChecked -Arguments @('--terminate',$Distribution)
            # Launch the distribution again and allow PID 1 startup to complete.
            Invoke-WslChecked -Arguments @('-d',$Distribution,'-u','root','--','true')
            Start-Sleep -Seconds 3
        }
        Invoke-WslChecked -Arguments @('-d',$Distribution,'-u','root','--','bash',$linuxPath,'install')
        Write-Host 'Docker and Compose installed inside WSL. Run -Stage Swarm for a single-node manager.'
    } else {
        $arguments = @('-d',$Distribution,'-u','root','--','bash',$linuxPath,'swarm')
        if ($AdvertiseAddress) {
            if ($AdvertiseAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) { throw 'Use an IPv4 WSL address.' }
            $arguments += $AdvertiseAddress.IPAddressToString
        }
        Invoke-WslChecked -Arguments $arguments
    }
} finally {
    Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
}
