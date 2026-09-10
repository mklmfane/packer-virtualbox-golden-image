packer {
  required_version = ">= 1.9.0"
  required_plugins {
    virtualbox = {
      source  = "github.com/hashicorp/virtualbox"
      version = "= 1.1.5"
    }
  }
}

source "virtualbox-ovf" "node" {
  source_path          = abspath(var.golden_image)
  checksum             = "sha256:${filesha256(abspath(var.golden_image))}"
  vm_name              = var.vm_name
  headless             = var.headless
  guest_additions_mode = "disable"
  ssh_username         = var.ssh_username
  ssh_private_key_file = pathexpand(var.ssh_private_key_file)
  ssh_timeout          = "20m"
  host_port_min        = 2222
  host_port_max        = 2299
  keep_registered      = true
  skip_export          = true
  output_directory     = "${path.root}/output/${var.vm_name}"
  shutdown_command     = "sudo -n shutdown -P now"
  shutdown_timeout     = "15m"
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--cpus", "${var.cpus}", "--memory", "${var.memory}"],
    ["modifyvm", "{{.Name}}", "--nic2", "hostonly", "--hostonlyadapter2", var.hostonly_adapter, "--cableconnected2", "on"],
    ["setextradata", "{{.Name}}", "lab.project", "packer-virtualbox-golden-image"]
  ]
}

build {
  sources = ["source.virtualbox-ovf.node"]
  provisioner "shell" {
    inline = ["sudo -n cloud-init status --wait"]
  }
  provisioner "file" {
    content     = jsonencode({ hostname = var.vm_name, node_ip = var.node_ip, ssh_username = var.ssh_username })
    destination = "/tmp/lab-node.json"
  }
  provisioner "shell" {
    inline = ["sudo -n install -m 0600 /tmp/lab-node.json /etc/lab-node.json", "rm /tmp/lab-node.json"]
  }
  provisioner "shell" {
    script          = "${path.root}/../scripts/configure-node.sh"
    execute_command = "chmod +x {{ .Path }}; sudo -n bash '{{ .Path }}'"
  }
  provisioner "shell" {
    inline = ["sudo -n touch /etc/lab-provisioned"]
  }
}
