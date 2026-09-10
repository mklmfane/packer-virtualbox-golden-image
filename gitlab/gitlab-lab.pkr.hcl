packer {
  required_version = ">= 1.9.0"

  required_plugins {
    virtualbox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/virtualbox"
    }
  }
}


source "virtualbox-iso" "gitlab-lab" {
  vm_name       = var.gitlab_vm_name
  guest_os_type = "Ubuntu_64"

  cpus      = var.cpus
  memory    = var.memory
  disk_size = var.disk_size

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  headless = var.headless

  # cloud-init seed ISO (NoCloud)
  cd_files = [
    "${path.root}/http/user-data",
    "${path.root}/http/meta-data"
  ]
  cd_label = "CIDATA"

  boot_wait = "10s"
  boot_command = [
    "<esc><wait>",
    "c<wait>",
    "linux /casper/vmlinuz autoinstall \"ds=nocloud\" cloud-config-url=/dev/null ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]

  communicator         = "ssh"
  ssh_username         = var.ssh_username
  ssh_private_key_file = pathexpand(var.ssh_private_key_file)
  ssh_agent_auth       = false
  ssh_timeout          = "20m"
  guest_additions_mode = "disable"

  # Packer will NAT-forward host 2222 -> guest 22 during build
  ssh_host_port_min = 2222
  ssh_host_port_max = 2222

  # Also forward GitLab HTTP: host 8080 -> guest 8080
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--natpf1", "http,tcp,,8080,,8080"]
  ]

  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  shutdown_timeout = "20m"

  output_directory = "${path.root}/output/gitlab-lab"
  format           = "ova"
  keep_registered = true
}

build {
  sources = ["source.virtualbox-iso.gitlab-lab"]

  provisioner "shell" {
    environment_vars = [
      "EXTERNAL_URL=${var.external_url}",
      "DEBIAN_FRONTEND=noninteractive",
      "NEEDRESTART_SUSPEND=1"
    ]
    execute_command = "sudo -E bash '{{ .Path }}'"
    scripts = [
      "${path.root}/scripts/00-preflight.sh",
      "${path.root}/scripts/10-install-gitlab.sh",
      "${path.root}/scripts/20-install-runner.sh",
      "${path.root}/scripts/30-install-docker.sh",
      "${path.root}/scripts/90-cleanup.sh",
    ]
  }
}
