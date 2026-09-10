packer {
  required_version = ">= 1.9.0"

  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = ">= 1.1.0"
    }
  }
}

source "virtualbox-iso" "ubuntu2404" {
  vm_name       = "ubuntu-2404-k8s-template"
  guest_os_type = "Ubuntu_64"
  headless      = true

  cpus      = 2
  memory    = 2048
  disk_size = 20000

  iso_url      = "https://releases.ubuntu.com/noble/ubuntu-24.04.3-live-server-amd64.iso"
  iso_checksum = "file:https://releases.ubuntu.com/noble/SHA256SUMS"

  # IMPORTANT: make output dir explicit so your OVF path is stable
  output_directory = "output-ubuntu2404"

  http_content = {
    "/user-data" = templatefile("${path.root}/http/user-data.pkrtpl", {
      ssh_username  = var.ssh_username
      ssh_pubkey    = var.ssh_pubkey
      hostname      = var.vm_hostname
      password_hash = var.password_hash
    })
    "/meta-data" = file("${path.root}/http/meta-data")
  }

  ssh_username         = var.ssh_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "45m"

  host_port_min = 2222
  host_port_max = 2222

  boot_wait = "10s"
  boot_command = [
    "<esc><wait>",
    "<esc><wait>",
    "c<wait5>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://10.0.2.2:{{ .HTTPPort }}/ ip=dhcp ---<enter><wait5>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>"
  ]

  shutdown_command = "sudo shutdown -P now"
  shutdown_timeout = "20m"
}

build {
  sources = ["source.virtualbox-iso.ubuntu2404"]

  # Run AFTER export => OVF exists here
  post-processor "shell-local" {
    environment_vars = [
      "OVF=${path.root}/output-ubuntu2404/ubuntu-2404-k8s-template.ovf",
      "HOSTONLY=auto",
      "SSH_USER=${var.ssh_username}",
      "SSH_KEY=${var.ssh_private_key_file}",
      "HOSTONLY_IP=192.168.56.1",
      "HOSTONLY_MASK=255.255.255.0"
    ]
    inline = [
      "bash ${path.root}/deploy-3nodes.sh"
    ]
  }
}
