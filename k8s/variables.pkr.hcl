variable "golden_image" {
  type    = string
  default = "../ubuntu2404-golden-image/output-ubuntu2404/ubuntu-2404-k8s-template.ovf"
}

variable "ssh_username" {
  type    = string
  default = "ubuntu"
}

variable "ssh_private_key_file" {
  type    = string
  default = "~/.ssh/kubernetes-packer-lab"
}

variable "vm_name" {
  type = string
}

variable "node_ip" {
  type = string
}

variable "hostonly_adapter" {
  type    = string
  default = "vboxnet0"
}

variable "cpus" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "headless" {
  type    = bool
  default = true
}

variable "role" {
  type    = string
  default = "worker"
}

variable "control_ip" {
  type    = string
  default = "192.168.56.10"
}

variable "pod_cidr" {
  type    = string
  default = "172.16.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "172.17.0.0/18"
}

variable "kubernetes_minor" {
  type    = string
  default = "1.36"
}

variable "calico_version" {
  type    = string
  default = "3.32.2"
}
