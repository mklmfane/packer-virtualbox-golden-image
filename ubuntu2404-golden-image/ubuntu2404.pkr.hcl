packer {
  required_version = ">= 1.9.0"
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "= 1.1.5"
    }
  }
}

source "virtualbox-iso" "ubuntu2404" {
  vm_name              = "ubuntu-2404-k8s-template"
  guest_os_type        = "Ubuntu_64"
  firmware             = "bios"
  headless             = var.headless
  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_size
  hard_drive_interface = "sata"
  guest_additions_mode = "disable"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  format           = "ovf"
  export_opts      = ["--ovf20"]
  output_directory = "${path.root}/output-ubuntu2404"

  http_content = {
    "/user-data" = templatefile("${path.root}/http/user-data.pkrtpl", {
      ssh_username  = var.ssh_username
      ssh_pubkey    = trimspace(file(pathexpand(var.ssh_public_key_file)))
      hostname      = var.vm_hostname
      password_hash = var.password_hash
    })
    "/meta-data" = file("${path.root}/http/meta-data")
  }
  http_bind_address = "0.0.0.0"
  http_port_min     = 8800
  http_port_max     = 8899

  ssh_username           = var.ssh_username
  ssh_private_key_file   = pathexpand(var.ssh_private_key_file)
  ssh_timeout            = "45m"
  ssh_handshake_attempts = 100
  host_port_min          = 2222
  host_port_max          = 2299

  boot_wait              = "10s"
  boot_keygroup_interval = "100ms"
  boot_command = [
    "<esc><wait>",
    "<esc><wait>",
    "c<wait5>",
    "linux /casper/vmlinuz autoinstall ds=nocloud-net\\;s=http://10.0.2.2:{{ .HTTPPort }}/ ip=dhcp ---<enter><wait5>",
    "initrd /casper/initrd<enter><wait5>",
    "boot<enter>"
  ]

  shutdown_command = "sudo -n /usr/local/sbin/seal-golden-image"
  shutdown_timeout = "20m"
}

build {
  sources = ["source.virtualbox-iso.ubuntu2404"]

  provisioner "shell" {
    inline = ["sudo -n cloud-init status --wait"]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -n bash '{{ .Path }}'"
    script          = "${path.root}/scripts/prepare-image.sh"
  }

  provisioner "file" {
    source      = "${path.root}/scripts/seal-golden-image.sh"
    destination = "/tmp/seal-golden-image.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo -n install -o root -g root -m 0750 /tmp/seal-golden-image.sh /usr/local/sbin/seal-golden-image",
      "rm /tmp/seal-golden-image.sh",
      "sudo -n test -s /etc/image-build-info",
      "sudo -n systemctl is-enabled golden-image-ssh-keys.service"
    ]
  }

  # Node deployment is a separate operation after a successful export.
}

