# Runs automatically at administrator logon, never under SYSTEM or the build account.
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.IsSystem -or $env:USERNAME -ieq 'packer') { exit 0 }
$state = 'C:\ProgramData\WindowsLab'
if (Test-Path "$state\complete.json") { exit 0 }
$ownerFile = "$state\owner.sid"
if (Test-Path $ownerFile) {
    if ((Get-Content $ownerFile -Raw).Trim() -ne $identity.User.Value) { exit 0 }
} else { $identity.User.Value | Set-Content $ownerFile }
New-Item -ItemType Directory -Force "$state\logs" | Out-Null
Start-Transcript -Path (Join-Path "$state\logs" ('postdeploy-' + (Get-Date -Format yyyyMMdd-HHmmss) + '.log'))
try {
    $installer = 'C:\WindowsLab\Install-WslDocker.ps1'
    foreach ($stage in @('Runtime','Ubuntu','Docker')) {
        $marker = "$state\$stage.done"
        if (Test-Path $marker) { continue }
        Write-Host "Starting automatic stage: $stage"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Stage $stage
        $rc = $LASTEXITCODE
        if ($rc -eq 3010) {
            New-Item -ItemType File -Force $marker | Out-Null
            Write-Host 'A reboot is required. Windows will restart in 60 seconds; sign in with the same account to continue.'
            & shutdown.exe /r /t 60 /c 'WindowsLab: WSL installation requires restart. Sign in again to continue.'
            if ($LASTEXITCODE -ne 0) { throw 'Could not schedule the required restart.' }
            exit 0
        }
        if ($rc -ne 0) { throw "Stage $stage failed (exit $rc). See this log; remaining stages were not run." }
        New-Item -ItemType File -Force $marker | Out-Null
    }
    $settings = Get-Content C:\WindowsLab\postdeploy-settings.json -Raw | ConvertFrom-Json
    if ($settings.initialize_swarm -and !(Test-Path "$state\Swarm.done")) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Stage Swarm
        if ($LASTEXITCODE -ne 0) { throw 'Swarm initialization failed.' }
        New-Item -ItemType File -Force "$state\Swarm.done" | Out-Null
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Stage Verify
    if ($LASTEXITCODE -ne 0) { throw 'Final Docker verification failed.' }
    @{ user=$identity.Name; sid=$identity.User.Value; completed=(Get-Date).ToString('o'); distro='Ubuntu-24.04' } | ConvertTo-Json | Set-Content "$state\complete.json"
    Disable-ScheduledTask -TaskName WindowsLab-PostDeploy | Out-Null
    Write-Host 'WSL, Linux Docker Engine and Compose are installed and verified. Swarm commands are available.'
} catch {
    $_ | Out-String | Set-Content "$state\last-error.txt"
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally { Stop-Transcript }
