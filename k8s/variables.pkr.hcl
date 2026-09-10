# K8s variables MUST have defaults, otherwise building any target will error
variable "cluster_name" {
  type    = string
  default = "Kubernetes_Cluster"
}

variable "k8s_vm_name" {
  type    = string
  default = "k8s-node"
}


variable "control_ip" {
  type    = string
  default = "192.168.56.10"
}

variable "worker_count" {
  type    = number
  default = 2
}

variable "dns_servers" {
  type    = list(string)
  default = ["8.8.8.8", "1.1.1.1"]
}

variable "pod_cidr" {
  type    = string
  default = "172.16.1.0/16"
}

variable "service_cidr" {
  type    = string
  default = "172.17.1.0/18"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34.*"
}

variable "calico_version" {
  type    = string
  default = "3.30.3"
}

variable "dashboard_version" {
  type    = string
  default = "2.7.0" # set to "2.7.0" if you want it
}

# These are only used by k8s-node builds, but must still have defaults
variable "role" {
  type    = string
  default = "worker" # or "controlplane"
}

variable "node_ip" {
  type    = string
  default = "192.168.56.21"
}

variable "headless" {
  type    = bool
  default = true
}

variable "iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/noble/ubuntu-24.04.3-live-server-amd64.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:c3514bf0056180d09376462a7a1b4f213c1d6e8ea67fae5c25099c6fd3d8274b"
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/id_ed25519_packer_gitlab"
}

variable "hostonly_adapter" {
  type    = string
  default = "vboxnet0"
}
