packer {
  required_version = ">= 1.9.0"
  required_plugins {
    virtualbox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/virtualbox"
    }
  }
}

source "virtualbox-iso" "k8s-base" {
  vm_name       = "k8s-base-ubuntu-24-04"
  guest_os_type = "Ubuntu_64"

  cpus      = 2
  memory    = 2048
  disk_size = 30000

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  headless             = var.headless
  guest_additions_mode = "disable"

  cd_label = "CIDATA"
  cd_files = [
    "${path.root}/http/user-data",
    "${path.root}/http/meta-data",
  ]

  boot_wait = "10s"

  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    " autoinstall ds=nocloud\\; cloud-config-url=/dev/null ---",
    "<f10><wait>"
  ]

  communicator         = "ssh"
  ssh_username         = var.ssh_username
  ssh_private_key_file = pathexpand(var.ssh_private_key_file)
  ssh_timeout          = "30m"

  ssh_host_port_min = 2222
  ssh_host_port_max = 2222

  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--nic2", "hostonly"],
    ["modifyvm", "{{.Name}}", "--hostonlyadapter2", var.hostonly_adapter],
    ["modifyvm", "{{.Name}}", "--cableconnected2", "on"],
  ]

  shutdown_command = "sudo shutdown -P now"
  shutdown_timeout = "15m"

  output_directory = "${path.root}/output/k8s-base"
  format           = "ova"
  keep_registered  = true
}

build {
  sources = ["source.virtualbox-iso.k8s-base"]

  provisioner "shell" {
    inline = [
      "mkdir -p /tmp/k8s-lab/bootstrap /tmp/k8s-lab/scripts",
      "sudo mkdir -p /opt/k8s-lab/bootstrap /opt/k8s-lab/scripts",
      "sudo apt-get update -y",
      "sudo apt-get install -y python3 ca-certificates curl",
    ]
  }

  provisioner "file" {
    source      = "${path.root}/bootstrap/"
    destination = "/tmp/k8s-lab/bootstrap/"
  }

  provisioner "file" {
    source      = "${path.root}/scripts/"
    destination = "/tmp/k8s-lab/scripts/"
  }

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    inline = [
      "cp -a /tmp/k8s-lab/bootstrap/. /opt/k8s-lab/bootstrap/",
      "cp -a /tmp/k8s-lab/scripts/.   /opt/k8s-lab/scripts/",

      "chown -R root:root /opt/k8s-lab",
      "chmod 0755 /opt/k8s-lab /opt/k8s-lab/bootstrap /opt/k8s-lab/scripts",
      "chmod 0755 /opt/k8s-lab/bootstrap/*.sh /opt/k8s-lab/scripts/*.sh || true",

      "install -m 0644 /opt/k8s-lab/bootstrap/k8s-bootstrap.service /etc/systemd/system/k8s-bootstrap.service",
      "install -m 0644 /opt/k8s-lab/bootstrap/k8s-join-server.service /etc/systemd/system/k8s-join-server.service",
      "systemctl daemon-reload",

      "test -x /opt/k8s-lab/bootstrap/k8s-bootstrap.sh",
      "test -f /etc/systemd/system/k8s-bootstrap.service",
      "test -x /opt/k8s-lab/scripts/common.sh",
      "test -x /opt/k8s-lab/scripts/master.sh",
      "test -x /opt/k8s-lab/scripts/node.sh",
    ]
  }
}
