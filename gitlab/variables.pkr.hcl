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
  default = "~/.ssh/kubespray-lab"
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

variable "external_url" {
  type    = string
  default = "http://192.168.56.30:8080"
}
