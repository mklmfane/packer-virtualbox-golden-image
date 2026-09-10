locals {
  dns_netplan = join(", ", var.dns_servers)
  dns_space   = join(" ", var.dns_servers)
  k8s_short   = substr(var.kubernetes_version, 0, 4)

  control_last = parseint(split(".", var.control_ip)[3], 10)
  node_last    = parseint(split(".", var.node_ip)[3], 10)
  node_index   = local.node_last - local.control_last

  hostname = var.role == "controlplane" ? "controlplane" : format("node%02d", local.node_index)
}

source "virtualbox-ovf" "k8s-node" {
  source_path = "${path.root}/output/k8s-base/k8s-base-ubuntu-24-04.ova"
  checksum    = "none"

  vm_name              = var.k8s_vm_name
  headless             = true
  guest_additions_mode = "disable"

  communicator         = "ssh"
  ssh_username         = var.ssh_username
  ssh_private_key_file = pathexpand(var.ssh_private_key_file)
  ssh_timeout          = "10m"

  skip_export     = true
  keep_registered = true

  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--nic2", "hostonly"],
    ["modifyvm", "{{.Name}}", "--hostonlyadapter2", var.hostonly_adapter],
    ["modifyvm", "{{.Name}}", "--cableconnected2", "on"]
  ]

  shutdown_command = "sudo shutdown -P now"
  shutdown_timeout = "10m"

  output_directory = "${path.root}/output/k8s-nodes/${var.k8s_vm_name}"
}

build {
  sources = ["source.virtualbox-ovf.k8s-node"]

  provisioner "shell" {
    execute_command = "sudo -E bash '{{ .Path }}'"
    inline = [
      "hostnamectl set-hostname ${local.hostname}",
      "mkdir -p /opt/k8s-share",

      "cat >/etc/k8s-lab.env <<'EOF'\nROLE=${var.role}\nNODE_IP=${var.node_ip}\nCONTROL_IP=${var.control_ip}\nWORKER_COUNT=${var.worker_count}\nDNS_SERVERS=\"${local.dns_space}\"\nDNS_SERVERS_NETPLAN=\"${local.dns_netplan}\"\nPOD_CIDR=${var.pod_cidr}\nSERVICE_CIDR=${var.service_cidr}\nKUBERNETES_VERSION=${var.kubernetes_version}\nKUBERNETES_VERSION_SHORT=${local.k8s_short}\nCALICO_VERSION=${var.calico_version}\nDASHBOARD_VERSION=${var.dashboard_version}\nJOIN_SERVER_PORT=8081\nEOF",
      "chmod 600 /etc/k8s-lab.env",

      "systemctl enable k8s-bootstrap.service",

      "test -f /etc/k8s-lab.env",
      "test -f /etc/systemd/system/k8s-bootstrap.service"
    ]
  }
}
