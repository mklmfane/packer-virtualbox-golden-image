packer {
  required_version = ">= 1.9.0"
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "= 1.1.5"
    }
  }
}
source "virtualbox-iso" "windows" {
  vm_name              = "server2022-container-template"
  guest_os_type        = "Windows2022_64"
  firmware             = "efi"
  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_size
  headless             = var.headless
  hard_drive_interface = "sata"
  #guest_additions_mode = "upload"
  #guest_additions_path = "C:/Windows/Temp/VBoxGuestAdditions.iso"
  
  guest_additions_mode      = "attach"
  guest_additions_interface = "ide"
  iso_url              = var.iso_url
  iso_checksum         = var.iso_checksum
  format               = "ovf"
  output_directory     = "${path.root}/output-server2022"
  communicator         = "winrm"
  winrm_username       = "packer"
  winrm_password       = var.admin_password
  winrm_use_ssl        = true
  winrm_insecure       = true
  winrm_use_ntlm       = true
  winrm_port           = 5986
  winrm_timeout        = "90m"
  host_port_min        = 2500
  host_port_max        = 2599
  cd_label             = "PACKERSEED"
  cd_content = {
    "Autounattend.xml" = templatefile("${path.root}/../shared/Autounattend.xml.pkrtpl", {
      password   = var.admin_password
      image_name = replace(replace(replace(var.image_name, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
    })
    "Bootstrap-WinRM.ps1" = file("${path.root}/../shared/scripts/Bootstrap-WinRM.ps1")
  }

  boot_wait = "1s"

  boot_command = [
    "<spacebar><wait1>",
    "<spacebar><wait1>",
    "<spacebar><wait1>",
    "<spacebar><wait1>",
    "<spacebar><wait1>",
    "<spacebar><wait1>",
    "<spacebar><wait1>",
    "<spacebar><wait1>",
    "<spacebar><wait1>",
    "<spacebar><wait1>"
  ]
  
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--rtc-use-utc", "on", "--nested-hw-virt", "on"],
    ["modifyvm", "{{.Name}}", "--graphicscontroller", "vboxsvga", "--vram", "128", "--accelerate-3d", "off"]
  ]

  shutdown_command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\\WindowsLab\\Seal-Image.ps1"
  shutdown_timeout = "30m"
}
build {
  sources = ["source.virtualbox-iso.windows"]
  provisioner "powershell" {
    inline = ["New-Item -ItemType Directory -Force C:\\WindowsLab | Out-Null"]
  }

  provisioner "file" {
    source      = "${path.root}/../shared/scripts/"
    destination = "C:/WindowsLab/"
  }

  provisioner "powershell" {
    inline = ["& C:\\WindowsLab\\Install-GuestAdditions.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    inline = ["& C:\\WindowsLab\\Test-GuestAdditions.ps1"]
  }

  provisioner "powershell" {
    inline = ["& C:\\WindowsLab\\Install-WslDocker.ps1 -Stage Features"]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    inline = [
      "& C:\\WindowsLab\\Test-GuestAdditions.ps1",
      "if (!(Get-WindowsFeature Containers).Installed) { throw 'Containers missing.' }",
      "foreach ($f in @('Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform')) { if ((Get-WindowsOptionalFeature -Online -FeatureName $f).State -ne 'Enabled') { throw ('Feature missing: ' + $f) } }",
      "Set-TimeZone -Id 'GTB Standard Time'"
    ]
  }

  provisioner "file" {
    content     = jsonencode({ initialize_swarm = var.initialize_swarm })
    destination = "C:/WindowsLab/postdeploy-settings.json"
  }

  provisioner "powershell" {
    inline = [
      "& C:\\WindowsLab\\Register-PostDeploy.ps1",
      "Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber | ConvertTo-Json | Set-Content C:\\WindowsLab\\image-build-info.json"
    ]
  }
}
