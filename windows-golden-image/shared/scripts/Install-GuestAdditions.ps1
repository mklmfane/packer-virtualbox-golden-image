#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$iso = 'C:\Windows\Temp\VBoxGuestAdditions.iso'
if (!(Test-Path $iso)) { throw 'Packer did not upload the Guest Additions ISO.' }
$image = Mount-DiskImage -ImagePath $iso -PassThru
try {
    $volume = $image | Get-Volume
    if (!$volume.DriveLetter) { throw 'Mounted Guest Additions ISO has no drive letter.' }
    $root = "$($volume.DriveLetter):\"
    $installer = Join-Path $root 'VBoxWindowsAdditions.exe'
    $signature = Get-AuthenticodeSignature $installer
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Oracle') {
        throw 'Guest Additions installer does not have a valid Oracle signature.'
    }
    # Trust only bundled publisher certificates from the host-matched GA media.
    $certDir = Join-Path $root 'cert'
    $certTool = Join-Path $certDir 'VBoxCertUtil.exe'
    if (Test-Path $certTool) {
        Push-Location $certDir
        try {
            & $certTool add-trusted-publisher 'vbox*.cer' --root 'vbox*.cer'
            if ($LASTEXITCODE -ne 0) { throw 'Guest Additions certificate import failed.' }
        } finally { Pop-Location }
    }
    $p = Start-Process -FilePath $installer -ArgumentList '/S' -Wait -PassThru
    if ($p.ExitCode -notin @(0,3010)) { throw "Guest Additions installer failed: $($p.ExitCode)" }
    Write-Host 'Guest Additions installed; Packer will now reboot and verify the service.'
} finally {
    Dismount-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue
}
