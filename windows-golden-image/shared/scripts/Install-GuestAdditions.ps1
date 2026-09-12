#Requires -Version 5.1
#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# Wait up to 60 seconds for Windows to discover the attached DVD.
$installer = $null

for ($attempt = 0; $attempt -lt 12; $attempt++) {
    $drives = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType = 5'

    foreach ($drive in $drives) {
        $candidate = Join-Path `
            ($drive.DeviceID + '\') `
            'VBoxWindowsAdditions.exe'

        if (Test-Path -LiteralPath $candidate) {
            $installer = $candidate
            break
        }
    }

    if ($installer) {
        break
    }

    Start-Sleep -Seconds 5
}

if (!$installer) {
    throw 'Guest Additions DVD not found. Set guest_additions_mode = "attach" in Packer.'
}

Write-Host "Guest Additions installer: $installer"

$signature = Get-AuthenticodeSignature -FilePath $installer

if (
    $signature.Status -ne 'Valid' -or
    $signature.SignerCertificate.Subject -notmatch 'Oracle'
) {
    throw 'Guest Additions installer does not have a valid Oracle signature.'
}

$root = Split-Path -Parent $installer
$certDirectory = Join-Path $root 'cert'
$certTool = Join-Path $certDirectory 'VBoxCertUtil.exe'

if (Test-Path -LiteralPath $certTool) {
    Push-Location $certDirectory

    try {
        & $certTool add-trusted-publisher 'vbox*.cer' --root 'vbox*.cer'

        if ($LASTEXITCODE -ne 0) {
            throw "Guest Additions certificate import failed: $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

$process = Start-Process `
    -FilePath $installer `
    -ArgumentList '/S' `
    -Wait `
    -PassThru

if ($process.ExitCode -notin @(0, 3010)) {
    throw "Guest Additions installation failed: $($process.ExitCode)"
}

Write-Host 'Guest Additions installed. Packer will reboot and verify VBoxService.'