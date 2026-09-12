. C:\WindowsLab\Common.ps1
$zip = Assert-Payload 'docker.zip'
$compose = Assert-Payload 'docker-compose.exe'
if (Get-Service docker -ErrorAction SilentlyContinue) { throw 'Docker already exists; use a fresh base installation.' }
Expand-Archive -Path $zip -DestinationPath 'C:\Program Files' -Force
if (!(Test-Path 'C:\Program Files\Docker\dockerd.exe')) { throw 'Expected official Windows Docker ZIP with docker/dockerd.exe.' }
# Standalone Compose on Server: docker-compose; Desktop already bundles docker compose.
Copy-Item $compose 'C:\Program Files\Docker\docker-compose.exe' -Force
$machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
[Environment]::SetEnvironmentVariable('Path', "$machinePath;C:\Program Files\Docker", 'Machine')
New-Item -ItemType Directory -Force C:\ProgramData\docker\config | Out-Null
'{"hosts":["npipe://"],"exec-opts":["isolation=process"]}' | Set-Content C:\ProgramData\docker\config\daemon.json -Encoding Ascii
& 'C:\Program Files\Docker\dockerd.exe' --register-service
if ($LASTEXITCODE -ne 0) { throw 'Docker service registration failed.' }
Set-Service docker -StartupType Automatic
Start-Service docker
for ($i=0; $i -lt 60; $i++) {
    & 'C:\Program Files\Docker\docker.exe' info *> $null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep 2
}
Invoke-Docker version
& 'C:\Program Files\Docker\docker-compose.exe' version
if ($LASTEXITCODE -ne 0) { throw 'Compose validation failed.' }
# Swarm is included in Docker Engine. Initialize it only on a deployed node.
