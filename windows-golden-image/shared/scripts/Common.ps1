$ErrorActionPreference = 'Stop'
function Assert-Payload([string]$Name) {
    $manifest = Get-Content C:\WindowsLab\payloads\manifest.json -Raw | ConvertFrom-Json
    $expected = $manifest.PSObject.Properties[$Name].Value
    $path = Join-Path C:\WindowsLab\payloads $Name
    if (!$expected -or (Get-FileHash $path -Algorithm SHA256).Hash -ne $expected) { throw "Payload checksum failed: $Name" }
    return $path
}
function Invoke-Docker {
    & 'C:\Program Files\Docker\docker.exe' @args
    if ($LASTEXITCODE -ne 0) { throw "docker failed with exit code $LASTEXITCODE" }
}
